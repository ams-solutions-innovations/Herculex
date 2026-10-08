import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_date_keys.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';

const String _legacySource = 'legacy_import';

/// One analysis to store as an assessment of kind `analysis`.
class AnalysisInput {
  const AnalysisInput({
    required this.analyzedAt,
    this.currentBfPercent,
    this.bfRangeMin,
    this.bfRangeMax,
    this.confidence = AssessmentConfidence.unknown,
    this.weightKg,
    this.summaryJson,
    this.source = 'ai',
    this.modelVersion,
    this.knowledgeVersion,
  });

  final DateTime analyzedAt;
  final double? currentBfPercent;
  final double? bfRangeMin;
  final double? bfRangeMax;
  final AssessmentConfidence confidence;
  final double? weightKg;
  final String? summaryJson;

  /// `ai` or `legacy_import`.
  final String source;
  final String? modelVersion;
  final String? knowledgeVersion;
}

/// Metadata for one photo row (bytes live in the photo store).
class NewPhotoRow {
  const NewPhotoRow({
    required this.pose,
    required this.relativePath,
    required this.takenAt,
    this.blurred = false,
    this.source = 'capture',
    this.legacyRef,
  });

  final String pose;
  final String relativePath;
  final bool blurred;
  final DateTime takenAt;
  final String source;
  final String? legacyRef;
}

class StartGoalInput {
  const StartGoalInput({
    this.goalSyncUuid,
    this.source = 'ai_analysis',
    this.targetAestheticStyle = '',
    this.timeframeRange = '',
    this.estimatedMonths,
    this.targetBfPercent,
    this.startWeightKg,
    this.startBfPercent,
    this.startedAt,
    this.analyses = const [],
    this.roadmap = const [],
    this.baselinePhotos = const [],
    this.archiveExisting = true,
    this.status = 'active',
  });

  final String? goalSyncUuid;
  final String source;
  final String targetAestheticStyle;
  final String timeframeRange;
  final int? estimatedMonths;
  final double? targetBfPercent;
  final double? startWeightKg;
  final double? startBfPercent;
  final DateTime? startedAt;
  final List<AnalysisInput> analyses;
  final List<RoadmapPhaseDraft> roadmap;
  final List<NewPhotoRow> baselinePhotos;
  final bool archiveExisting;
  final String status;
}

/// Persists physique goals, their analyses, proposed roadmaps and baseline
/// photo rows. Goals are archived, never deleted (D-03).
class PhysiqueGoalRepository {
  PhysiqueGoalRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  SimpleSelectStatement<$PhysiqueGoalsTable, PhysiqueGoalData> _activeRows() =>
      _db.select(_db.physiqueGoals)
        ..where((g) => g.deletedAt.isNull() & g.status.equals('active'));

  /// Non-legacy goals first, then greatest startedAt, then greatest id.
  static PhysiqueGoalData? _winner(List<PhysiqueGoalData> rows) {
    if (rows.isEmpty) return null;
    final sorted = [...rows]
      ..sort((a, b) {
        final la = a.source == _legacySource ? 1 : 0;
        final lb = b.source == _legacySource ? 1 : 0;
        if (la != lb) return la - lb;
        final c = b.startedAt.compareTo(a.startedAt);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    return sorted.first;
  }

  Stream<PhysiqueGoalData?> watchActiveGoal() =>
      _activeRows().watch().map(_winner);

  Future<PhysiqueGoalData?> getActiveGoal() async =>
      _winner(await _activeRows().get());

  Stream<List<PhysiqueGoalData>> watchArchivedGoals() {
    final q = _db.select(_db.physiqueGoals)
      ..where((g) => g.deletedAt.isNull() & g.status.equals('archived'))
      ..orderBy([
        (g) => OrderingTerm.desc(g.archivedAt),
        (g) => OrderingTerm.desc(g.id),
      ]);
    return q.watch();
  }

  Stream<PhysiqueGoalData?> watchGoal(int id) => (_db.select(
    _db.physiqueGoals,
  )..where((g) => g.id.equals(id) & g.deletedAt.isNull())).watchSingleOrNull();

  Future<PhysiqueGoalData?> getGoal(int id) => (_db.select(
    _db.physiqueGoals,
  )..where((g) => g.id.equals(id) & g.deletedAt.isNull())).getSingleOrNull();

  void _validate(StartGoalInput input) {
    final legacy = input.source == _legacySource;
    if (input.status != 'active' && input.status != 'archived') {
      throw ArgumentError.value(input.status, 'status');
    }
    if (input.status == 'archived' && !legacy) {
      throw ArgumentError.value(
        input.status,
        'status',
        'archived is only valid for legacy_import',
      );
    }
    if (!legacy) {
      if (input.analyses.isEmpty) {
        throw ArgumentError.value(input.analyses, 'analyses', 'required');
      }
      if (input.estimatedMonths == null || input.targetBfPercent == null) {
        throw ArgumentError('estimatedMonths and targetBfPercent are required');
      }
    }
  }

  Future<int> startGoal(StartGoalInput input) {
    _validate(input);
    return _db.transaction(() async {
      final now = _clock.now();
      final archivedOnInsert = input.status == 'archived';
      if (input.archiveExisting && !archivedOnInsert) {
        await _archiveActive(now);
      }
      final goalId = await _db
          .into(_db.physiqueGoals)
          .insert(
            PhysiqueGoalsCompanion(
              syncUuid: input.goalSyncUuid == null
                  ? const Value.absent()
                  : Value(input.goalSyncUuid),
              status: Value(input.status),
              source: Value(input.source),
              targetAestheticStyle: Value(input.targetAestheticStyle),
              timeframeRange: Value(input.timeframeRange),
              estimatedMonths: Value(input.estimatedMonths),
              targetBfPercent: Value(input.targetBfPercent),
              startWeightKg: Value(input.startWeightKg),
              startBfPercent: Value(input.startBfPercent),
              startedAt: Value(input.startedAt ?? now),
              archivedAt: Value(archivedOnInsert ? now : null),
            ),
          );

      final analyses = [...input.analyses]
        ..sort((a, b) => a.analyzedAt.compareTo(b.analyzedAt));
      int? newestAssessmentId;
      for (final a in analyses) {
        newestAssessmentId = await _db
            .into(_db.physiqueAssessments)
            .insert(
              PhysiqueAssessmentsCompanion.insert(
                goalId: goalId,
                kind: 'analysis',
                dateIso: physiqueDayKey(a.analyzedAt),
                assessedAt: Value(a.analyzedAt),
                weightKg: Value(a.weightKg),
                currentBfPercent: Value(a.currentBfPercent),
                bfRangeMin: Value(a.bfRangeMin),
                bfRangeMax: Value(a.bfRangeMax),
                confidence: Value(a.confidence.wireValue),
                source: Value(a.source),
                modelVersion: Value(a.modelVersion),
                knowledgeVersion: Value(a.knowledgeVersion),
                summaryJson: Value(a.summaryJson),
              ),
            );
      }

      for (var i = 0; i < input.roadmap.length; i++) {
        final d = input.roadmap[i];
        await _db
            .into(_db.physiqueRoadmapPhases)
            .insert(
              PhysiqueRoadmapPhasesCompanion.insert(
                goalId: goalId,
                orderIndex: i,
                phaseType: d.phase.name,
                plannedWeeks: d.plannedWeeks,
                targetWeightKg: Value(d.targetWeightKg),
                targetBfPercent: Value(d.targetBfPercent),
                weeklyRateKg: Value(d.weeklyRateKg),
                tempoCapped: Value(d.tempoCapped),
                status: const Value('upcoming'),
              ),
            );
      }

      for (final p in input.baselinePhotos) {
        await _insertPhoto(goalId, p, newestAssessmentId);
      }
      return goalId;
    });
  }

  /// Stores a fresh analysis of an active goal together with the roadmap built
  /// from it, in one transaction: the analysis row, its photo (role
  /// `checkin`), the goal's new time estimate and target body fat, and the
  /// replacement roadmap.
  ///
  /// The running phase is closed as done when the new roadmap starts with a
  /// different phase, so its history stays on the timeline. When it starts
  /// with the same phase the repository carries the start date over.
  Future<int> applyReanalysis({
    required int goalId,
    required AnalysisInput analysis,
    required int estimatedMonths,
    required double targetBfPercent,
    required List<RoadmapPhaseDraft> roadmap,
    NewPhotoRow? photo,
  }) {
    if (roadmap.isEmpty) {
      throw ArgumentError.value(roadmap, 'roadmap', 'must not be empty');
    }
    return _db.transaction(() async {
      final goal = await getGoal(goalId);
      if (goal == null || goal.status != 'active') {
        throw StateError('Physique goal $goalId is not active');
      }
      final now = _clock.now();

      final assessmentId = await _db
          .into(_db.physiqueAssessments)
          .insert(
            PhysiqueAssessmentsCompanion.insert(
              goalId: goalId,
              kind: 'analysis',
              dateIso: physiqueDayKey(analysis.analyzedAt),
              assessedAt: Value(analysis.analyzedAt),
              weightKg: Value(analysis.weightKg),
              currentBfPercent: Value(analysis.currentBfPercent),
              bfRangeMin: Value(analysis.bfRangeMin),
              bfRangeMax: Value(analysis.bfRangeMax),
              confidence: Value(analysis.confidence.wireValue),
              source: Value(analysis.source),
              modelVersion: Value(analysis.modelVersion),
              knowledgeVersion: Value(analysis.knowledgeVersion),
              summaryJson: Value(analysis.summaryJson),
            ),
          );
      if (photo != null) {
        await _insertPhoto(goalId, photo, assessmentId, role: 'checkin');
      }

      await (_db.update(
        _db.physiqueGoals,
      )..where((g) => g.id.equals(goalId))).write(
        PhysiqueGoalsCompanion(
          estimatedMonths: Value(estimatedMonths),
          targetBfPercent: Value(targetBfPercent),
          updatedAt: Value(now),
        ),
      );

      final current =
          await (_db.select(_db.physiqueRoadmapPhases)..where(
                (p) =>
                    p.goalId.equals(goalId) &
                    p.status.equals('current') &
                    p.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (current != null && current.phaseType != roadmap.first.phase.name) {
        await (_db.update(
          _db.physiqueRoadmapPhases,
        )..where((p) => p.id.equals(current.id))).write(
          PhysiqueRoadmapPhasesCompanion(
            status: const Value('done'),
            completedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      await PhysiqueRoadmapRepository(
        _db,
        _clock,
      ).replaceRoadmap(goalId, roadmap);
      return assessmentId;
    });
  }

  Future<void> _insertPhoto(
    int goalId,
    NewPhotoRow p,
    int? assessmentId, {
    String role = 'baseline',
  }) => _db
      .into(_db.physiquePhotos)
      .insert(
        PhysiquePhotosCompanion.insert(
          goalId: goalId,
          assessmentId: Value(assessmentId),
          role: role,
          pose: p.pose,
          dateIso: physiqueDayKey(p.takenAt),
          takenAt: Value(p.takenAt),
          relativePath: p.relativePath,
          blurred: Value(p.blurred),
          source: Value(p.source),
          legacyRef: Value(p.legacyRef),
        ),
      );

  Future<int> _archiveActive(DateTime now, {int? exceptId}) async {
    final rows = await _activeRows().get();
    var n = 0;
    for (final g in rows) {
      if (g.id == exceptId) continue;
      await (_db.update(
        _db.physiqueGoals,
      )..where((t) => t.id.equals(g.id))).write(
        PhysiqueGoalsCompanion(
          status: const Value('archived'),
          archivedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      n++;
    }
    return n;
  }

  Future<void> archiveGoal(int goalId) => _db.transaction(() async {
    final now = _clock.now();
    await (_db.update(
      _db.physiqueGoals,
    )..where((t) => t.id.equals(goalId))).write(
      PhysiqueGoalsCompanion(
        status: const Value('archived'),
        archivedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });

  /// Archives every active goal except the winner; returns how many.
  Future<int> reconcileSingleActive() => _db.transaction(() async {
    final winner = _winner(await _activeRows().get());
    if (winner == null) return 0;
    return _archiveActive(_clock.now(), exceptId: winner.id);
  });

  Future<bool> hasLegacyImportGoal() async =>
      await getLegacyImportGoal() != null;

  Future<PhysiqueGoalData?> getLegacyImportGoal() =>
      (_db.select(_db.physiqueGoals)
            ..where(
              (g) => g.deletedAt.isNull() & g.source.equals(_legacySource),
            )
            ..orderBy([(g) => OrderingTerm.asc(g.id)])
            ..limit(1))
          .getSingleOrNull();

  /// Every stored legacyRef, soft-deleted rows included.
  Future<Set<String>> legacyPhotoRefs() async {
    final rows = await (_db.select(
      _db.physiquePhotos,
    )..where((p) => p.legacyRef.isNotNull())).get();
    return {for (final r in rows) r.legacyRef!};
  }

  /// Idempotent append of legacy baseline photos; returns inserted count.
  Future<int> appendLegacyPhotos(int goalId, List<NewPhotoRow> photos) =>
      _db.transaction(() async {
        final goal = await getGoal(goalId);
        if (goal == null) {
          throw StateError('Physique goal $goalId not found');
        }
        final seen = await legacyPhotoRefs();
        var inserted = 0;
        for (final p in photos) {
          final ref = p.legacyRef;
          if (ref != null && !seen.add(ref)) continue;
          await _insertPhoto(
            goalId,
            NewPhotoRow(
              pose: p.pose,
              relativePath: p.relativePath,
              takenAt: p.takenAt,
              blurred: p.blurred,
              source: _legacySource,
              legacyRef: ref,
            ),
            null,
          );
          inserted++;
        }
        return inserted;
      });
}
