import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Persists a goal's roadmap and its explicit advance/postpone transitions
/// (D-01, D-02). Never touches nutrition targets.
class PhysiqueRoadmapRepository {
  PhysiqueRoadmapRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  Stream<List<PhysiqueRoadmapPhaseData>> watchPhases(int goalId) {
    final q = _db.select(_db.physiqueRoadmapPhases)
      ..where((p) => p.goalId.equals(goalId) & p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]);
    return q.watch();
  }

  Future<List<PhysiqueRoadmapPhaseData>> _phases(int goalId) =>
      (_db.select(_db.physiqueRoadmapPhases)
            ..where((p) => p.goalId.equals(goalId) & p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]))
          .get();

  Future<PhysiqueGoalData> _activeGoal(int goalId) async {
    final goal =
        await (_db.select(_db.physiqueGoals)
              ..where((g) => g.id.equals(goalId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (goal == null || goal.status != 'active') {
      throw StateError('Physique goal $goalId is not active');
    }
    return goal;
  }

  Future<void> replaceRoadmap(
    int goalId,
    List<RoadmapPhaseDraft> drafts, {
    bool accept = false,
  }) async {
    if (drafts.isEmpty) {
      throw ArgumentError.value(drafts, 'drafts', 'must not be empty');
    }
    await _db.transaction(() async {
      final goal = await _activeGoal(goalId);
      final now = _clock.now();
      final existing = await _phases(goalId);
      final accepted = goal.roadmapAcceptedAt != null;
      final acceptNow = accept && !accepted;
      final live = accepted || acceptNow;

      final doneIds = accepted
          ? {
              for (final p in existing)
                if (p.status == 'done') p.id,
            }
          : <int>{};
      PhysiqueRoadmapPhaseData? prevCurrent;
      for (final p in existing) {
        if (p.status == 'current') {
          prevCurrent = p;
          break;
        }
      }

      for (final p in existing) {
        if (doneIds.contains(p.id)) continue;
        await (_db.delete(
          _db.physiqueRoadmapPhases,
        )..where((t) => t.id.equals(p.id))).go();
      }

      final base = doneIds.length;
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final isCurrent = live && i == 0;
        DateTime? startedAt;
        if (isCurrent) {
          startedAt =
              (prevCurrent != null &&
                  prevCurrent.phaseType == d.phase.name &&
                  prevCurrent.startedAt != null)
              ? prevCurrent.startedAt
              : now;
        }
        await _db
            .into(_db.physiqueRoadmapPhases)
            .insert(
              PhysiqueRoadmapPhasesCompanion.insert(
                goalId: goalId,
                orderIndex: base + i,
                phaseType: d.phase.name,
                plannedWeeks: d.plannedWeeks,
                targetWeightKg: Value(d.targetWeightKg),
                targetBfPercent: Value(d.targetBfPercent),
                weeklyRateKg: Value(d.weeklyRateKg),
                tempoCapped: Value(d.tempoCapped),
                status: Value(isCurrent ? 'current' : 'upcoming'),
                startedAt: Value(startedAt),
              ),
            );
      }

      if (acceptNow) {
        await (_db.update(
          _db.physiqueGoals,
        )..where((g) => g.id.equals(goalId))).write(
          PhysiqueGoalsCompanion(
            roadmapAcceptedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Explicit advance only (D-02). Returns false when there is no next phase.
  Future<bool> advancePhase(int goalId) => _db.transaction(() async {
    await _activeGoal(goalId);
    final now = _clock.now();
    final phases = await _phases(goalId);
    final upcoming = phases.where((p) => p.status == 'upcoming').toList();
    if (upcoming.isEmpty) return false;
    final next = upcoming.first;
    for (final p in phases.where((p) => p.status == 'current')) {
      await (_db.update(
        _db.physiqueRoadmapPhases,
      )..where((t) => t.id.equals(p.id))).write(
        PhysiqueRoadmapPhasesCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
    await (_db.update(
      _db.physiqueRoadmapPhases,
    )..where((t) => t.id.equals(next.id))).write(
      PhysiqueRoadmapPhasesCompanion(
        status: const Value('current'),
        startedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await (_db.update(
      _db.physiqueGoals,
    )..where((g) => g.id.equals(goalId))).write(
      PhysiqueGoalsCompanion(
        advanceSnoozedUntil: const Value(null),
        updatedAt: Value(now),
      ),
    );
    return true;
  });

  Future<void> postponeAdvance(int goalId) => _db.transaction(() async {
    await _activeGoal(goalId);
    final now = _clock.now();
    final until = DateTime(
      now.year,
      now.month,
      now.day + PhysiqueTuning.advancePostponeDays,
    );
    await (_db.update(
      _db.physiqueGoals,
    )..where((g) => g.id.equals(goalId))).write(
      PhysiqueGoalsCompanion(
        advanceSnoozedUntil: Value(until),
        updatedAt: Value(now),
      ),
    );
  });
}
