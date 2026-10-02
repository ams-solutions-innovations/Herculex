import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _legacySource = 'legacy_import';
const String _reportedKey =
    'herculex.physique_legacy_migration.v2_reported_unrecoverable';

class LegacyMigrationResult {
  const LegacyMigrationResult({
    this.ran = false,
    this.analyses = 0,
    this.photosMigrated = 0,
    this.photosUnrecoverable = 0,
    this.goalId,
  });

  /// True when anything was created, migrated or cleaned up.
  final bool ran;
  final int analyses;
  final int photosMigrated;

  /// Only ids not reported by an earlier run.
  final int photosUnrecoverable;
  final int? goalId;

  bool get hasNotice => photosMigrated > 0 || photosUnrecoverable > 0;
}

/// Moves the SharedPreferences Dream Physique history and the legacy
/// `progress_photos` rows into the physique tables (D-08).
///
/// There is no done flag: idempotency is derived from state (the
/// `legacy_import` goal plus the per-photo `legacyRef`), so rows that the
/// Measurements screen writes later are appended on the next launch.
/// Originals are deleted only after the database commit. Never calls an AI
/// backend and never reads nutrition tables.
class PhysiqueLegacyMigrator {
  PhysiqueLegacyMigrator({
    required AppDatabase db,
    required PhysiqueGoalRepository goals,
    required PhysiquePhotoSanitizer sanitizer,
    required PhysiquePhotoStore store,
    required DreamPhysiqueSummaryRepository summaries,
    required SharedPreferences prefs,
    required Profile? Function() readProfile,
    required Clock clock,
  }) : _db = db,
       _goals = goals,
       _sanitizer = sanitizer,
       _store = store,
       _summaries = summaries,
       _prefs = prefs,
       _readProfile = readProfile,
       _clock = clock;

  final AppDatabase _db;
  final PhysiqueGoalRepository _goals;
  final PhysiquePhotoSanitizer _sanitizer;
  final PhysiquePhotoStore _store;
  final DreamPhysiqueSummaryRepository _summaries;
  final SharedPreferences _prefs;
  final Profile? Function() _readProfile;
  final Clock _clock;

  Future<LegacyMigrationResult> run() async {
    final history = _summaries.history; // newest first
    final rows = await _db.select(_db.progressPhotos).get();
    final legacyGoal = await _goals.getLegacyImportGoal();
    final refs = await _goals.legacyPhotoRefs();

    // Crash recovery: copied by an earlier run that died before cleanup.
    var cleaned = 0;
    final pending = <ProgressPhotoData>[];
    for (final row in rows) {
      if (refs.contains(_refFor(row))) {
        await _deleteOriginal(row);
        cleaned++;
      } else {
        pending.add(row);
      }
    }

    if (legacyGoal == null && history.isEmpty && pending.isEmpty) {
      return LegacyMigrationResult(ran: cleaned > 0);
    }
    if (legacyGoal != null && pending.isEmpty) {
      return LegacyMigrationResult(ran: cleaned > 0, goalId: legacyGoal.id);
    }

    final String folderUuid;
    if (legacyGoal != null) {
      final uuid = legacyGoal.syncUuid;
      if (uuid == null) {
        throw StateError('Legacy goal ${legacyGoal.id} has no sync uuid');
      }
      folderUuid = uuid;
    } else {
      folderUuid = const Uuid().v4();
    }

    // Stage every pending row through the sanitiser (EXIF stripped on copy).
    final migrated = <(ProgressPhotoData, NewPhotoRow)>[];
    final unrecoverable = <int>[];
    for (final row in pending) {
      final file = File(row.filePath);
      if (!file.existsSync()) {
        unrecoverable.add(row.id);
        continue;
      }
      try {
        final staged = await _sanitizer.stage(file, blurFaces: false);
        final relative = await _store.adopt(staged.file, goalUuid: folderUuid);
        migrated.add((
          row,
          NewPhotoRow(
            pose: row.pose,
            relativePath: relative,
            takenAt: DateTime.tryParse(row.dateIso) ?? _clock.now(),
            source: _legacySource,
            legacyRef: _refFor(row),
          ),
        ));
      } on PhotoSanitizeException {
        unrecoverable.add(row.id);
      }
    }
    final photoRows = [for (final m in migrated) m.$2];

    int goalId;
    var analyses = 0;
    if (legacyGoal != null) {
      goalId = legacyGoal.id;
      if (migrated.isEmpty) {
        return LegacyMigrationResult(
          ran: cleaned > 0,
          goalId: goalId,
          photosUnrecoverable: await _reportNew(unrecoverable),
        );
      }
      try {
        await _goals.appendLegacyPhotos(goalId, photoRows);
      } catch (_) {
        for (final p in photoRows) {
          await _store.delete(p.relativePath);
        }
        rethrow;
      }
    } else {
      if (history.isEmpty && migrated.isEmpty) {
        return LegacyMigrationResult(
          ran: cleaned > 0,
          photosUnrecoverable: await _reportNew(unrecoverable),
        );
      }
      final input = _buildGoalInput(
        history: history,
        photoRows: photoRows,
        goalUuid: folderUuid,
        live: await _goals.getActiveGoal(),
      );
      try {
        goalId = await _db.transaction(() async {
          final id = await _goals.startGoal(input);
          // Legacy photos are not tied to an analysis (startGoal links
          // baseline photos to the newest assessment).
          await (_db.update(_db.physiquePhotos)
                ..where((p) => p.goalId.equals(id)))
              .write(const PhysiquePhotosCompanion(assessmentId: Value(null)));
          return id;
        });
      } catch (_) {
        await _store.deleteGoalFolder(folderUuid);
        rethrow;
      }
      analyses = history.length;
      await _goals.reconcileSingleActive();
    }

    // Committed: only now remove the originals and their rows.
    for (final m in migrated) {
      await _deleteOriginal(m.$1);
    }

    return LegacyMigrationResult(
      ran: true,
      analyses: analyses,
      photosMigrated: migrated.length,
      photosUnrecoverable: await _reportNew(unrecoverable),
      goalId: goalId,
    );
  }

  String _refFor(ProgressPhotoData row) => 'progress_photo:${row.id}';

  Future<void> _deleteOriginal(ProgressPhotoData row) async {
    try {
      final file = File(row.filePath);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best effort; the row is the record and is removed below.
    }
    await (_db.delete(
      _db.progressPhotos,
    )..where((p) => p.id.equals(row.id))).go();
  }

  /// Persists newly seen unrecoverable ids; returns how many were new.
  Future<int> _reportNew(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final seen = (_prefs.getStringList(_reportedKey) ?? const <String>[])
        .toSet();
    final fresh = ids.where((id) => !seen.contains('$id')).toList();
    if (fresh.isEmpty) return 0;
    seen.addAll(fresh.map((id) => '$id'));
    await _prefs.setStringList(_reportedKey, seen.toList());
    return fresh.length;
  }

  StartGoalInput _buildGoalInput({
    required List<DreamPhysiqueAnalysisSummary> history,
    required List<NewPhotoRow> photoRows,
    required String goalUuid,
    required PhysiqueGoalData? live,
  }) {
    // D-03: a legacy goal never displaces a live goal.
    final status = live == null ? 'active' : 'archived';

    if (history.isEmpty) {
      DateTime? earliest;
      for (final p in photoRows) {
        if (earliest == null || p.takenAt.isBefore(earliest)) {
          earliest = p.takenAt;
        }
      }
      return StartGoalInput(
        goalSyncUuid: goalUuid,
        source: _legacySource,
        startedAt: earliest ?? _clock.now(),
        analyses: const [],
        roadmap: const [
          RoadmapPhaseDraft(
            phase: DietPhase.maintain,
            plannedWeeks: 4,
            weeklyRateKg: 0,
          ),
        ],
        baselinePhotos: photoRows,
        archiveExisting: false,
        status: status,
      );
    }

    final newest = history.first;
    final oldest = history.last;
    final profile = _readProfile();
    final weight = profile?.weightKg;
    final List<RoadmapPhaseDraft> roadmap;
    if (weight != null && weight > 0) {
      roadmap = PhysiqueRoadmapGenerator.propose(
        PhysiqueRoadmapInput(
          weightKg: weight,
          currentBfPercent: newest.currentEstimatedBf,
          targetBfPercent: newest.targetBfPercent,
          plannedWeightChangeKg: newest.weightChangeKg,
          estimatedMonths: newest.estimatedMonths,
          ageYears: profile?.ageYears,
          confidence: AssessmentConfidence.unknown,
          prefersWeightLoss: profile?.goal == FitnessGoal.weightLoss,
        ),
      ).phases;
    } else {
      roadmap = const [
        RoadmapPhaseDraft(
          phase: DietPhase.maintain,
          plannedWeeks: 4,
          weeklyRateKg: 0,
        ),
      ];
    }

    return StartGoalInput(
      goalSyncUuid: goalUuid,
      source: _legacySource,
      targetAestheticStyle: newest.targetAestheticStyle,
      timeframeRange: newest.timeframeRange,
      estimatedMonths: newest.estimatedMonths,
      targetBfPercent: newest.targetBfPercent,
      startWeightKg: weight,
      startBfPercent: oldest.currentEstimatedBf,
      startedAt: oldest.analyzedAt,
      analyses: [
        for (final s in history.reversed)
          AnalysisInput(
            analyzedAt: s.analyzedAt,
            currentBfPercent: s.currentEstimatedBf,
            summaryJson: jsonEncode(s.toJson()),
            source: _legacySource,
          ),
      ],
      roadmap: roadmap,
      baselinePhotos: photoRows,
      archiveExisting: false,
      status: status,
    );
  }
}
