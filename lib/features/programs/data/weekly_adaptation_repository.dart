import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:health/health.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

part 'weekly_adaptation_repository/_plan_math.part.dart';
part 'weekly_adaptation_repository/_skip_proposal.part.dart';
part 'weekly_adaptation_repository/_proposal_inputs.part.dart';

class StoredAdaptationProposal {
  const StoredAdaptationProposal({
    required this.id,
    required this.proposal,
    required this.sourceScheduleId,
    this.exerciseNames = const {},
    this.scheduleDates = const {},
  });

  final int id;
  final AdaptationProposal proposal;
  final int sourceScheduleId;
  final Map<int, String> exerciseNames;
  final Map<int, String> scheduleDates;
}

class AdaptationStaleException implements Exception {
  const AdaptationStaleException();
  @override
  String toString() =>
      'Your plan or recovery changed. Reopen the suggestion to review an updated plan.';
}

/// Builds and persists the deterministic, current-week adaptation layer.
///
/// This repository is intentionally the only writer of adaptation rows.  The
/// UI gets a proposal first, then explicitly accepts or declines it.
class WeeklyAdaptationRepository {
  WeeklyAdaptationRepository(this._db, this._clock, {HealthService? health})
    : _health = health;

  final AppDatabase _db;
  final Clock _clock;
  final HealthService? _health;

  Future<StoredAdaptationProposal?> proposeForSkippedWorkout(int scheduleId) =>
      _propose(
        scheduleId: scheduleId,
        trigger: AdaptationTrigger.skippedWorkout,
      );

  /// Used after a session ends.  A fully completed session naturally has no
  /// deficit and returns null; callers therefore do not need to guess whether
  /// the user skipped an accessory or simply completed a shorter template.
  Future<StoredAdaptationProposal?> proposeForIncompleteWorkout(
    int scheduleId,
  ) => _propose(
    scheduleId: scheduleId,
    trigger: AdaptationTrigger.incompleteWorkout,
  );

  Future<StoredAdaptationProposal?> proposeForIncompleteSession(
    int sessionId,
  ) async {
    final schedule =
        await (_db.select(_db.scheduledWorkouts)
              ..where((table) => table.completedSessionId.equals(sessionId)))
            .getSingleOrNull();
    if (schedule == null) {
      return null;
    }
    return _propose(
      scheduleId: schedule.id,
      sourceSessionId: sessionId,
      trigger: AdaptationTrigger.incompleteWorkout,
    );
  }

  Future<StoredAdaptationProposal?> proposeForLowRecovery(
    int scheduleId, {
    required double volumeFactor,
    required String reason,
  }) async {
    final schedule = await (_db.select(
      _db.scheduledWorkouts,
    )..where((table) => table.id.equals(scheduleId))).getSingleOrNull();
    if (schedule == null || schedule.programId == null) {
      return null;
    }
    if (!ScheduleStatus.isOpen(schedule.status) ||
        schedule.completedSessionId != null ||
        schedule.deletedAt != null) {
      return null;
    }
    final original = await PlannedSessionResolver(
      _db,
    ).resolveScheduledWorkout(schedule);
    final acceptedRecovery =
        await (_db.select(_db.adaptationProposals)
              ..where(
                (p) =>
                    p.sourceScheduleId.equals(scheduleId) &
                    p.trigger.equals(AdaptationTrigger.lowRecovery.name) &
                    p.decision.equals(AdaptationDecision.accepted.name) &
                    p.deletedAt.isNull(),
              )
              ..orderBy([(p) => OrderingTerm.desc(p.id)])
              ..limit(1))
            .getSingleOrNull();
    if (acceptedRecovery != null) {
      final applied = _decode(
        acceptedRecovery.proposalJson,
      ).changes.single.plan;
      if (applied.encode() == _adaptedPlan(original).encode()) {
        return null;
      }
    }
    final catalog = await _db.select(_db.exerciseCatalog).get();
    final catalogById = {for (final exercise in catalog) exercise.id: exercise};
    final muscleRows = await _db.select(_db.exerciseMuscles).get();
    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final row in muscleRows) {
      musclesByExercise.putIfAbsent(row.exerciseId, () => []).add(row);
    }
    final plannedMuscles = <String, double>{};
    _addPlanVolume(plannedMuscles, original, musclesByExercise, catalogById);
    final recovery = await _recoveryByMuscle();
    final lowestRecovery = plannedMuscles.keys.fold<int>(
      100,
      (lowest, muscle) => math.min(lowest, recovery[muscle] ?? 100),
    );
    if (volumeFactor >= 1 &&
        lowestRecovery >= WeeklyAdaptationEngine.minimumRecoveryScore) {
      return null;
    }
    // A poor target-muscle recovery on its own gets a modest deterministic
    // accessory reduction. Sleep/activity may request a stricter factor.
    final effectiveFactor = volumeFactor >= 1
        ? 0.75
        : volumeFactor.clamp(0.0, 1.0).toDouble();
    final effectiveReason = volumeFactor >= 1
        ? 'Some target muscles are not recovered enough for the full accessory volume.'
        : reason;
    // CNS-sensitive sessions preserve the quality of the primary work instead of
    // blindly shaving every exercise.  The program guide treats forced reps as
    // inappropriate when neurological fatigue is high, so this caps compound
    // work at two existing working sets (without changing its intent) and
    // removes accessory/isolation sets to meet the requested volume factor.
    final reduced = _reducedPlan(original, effectiveFactor, catalogById);
    if (reduced.workingSetCount >= _adaptedPlan(original).workingSetCount) {
      return null;
    }
    final sourceDate = DateTime.tryParse(schedule.dateIso);
    if (sourceDate == null) {
      return null;
    }
    final weekStart = _monday(sourceDate);
    final fingerprint =
        '${schedule.id}|lowRecovery|$effectiveFactor|$effectiveReason|$lowestRecovery|${_adaptedPlan(original).encode()}';
    await _expireOtherProposals(
      scheduleId,
      AdaptationTrigger.lowRecovery,
      fingerprint,
    );
    var existing =
        await (_db.select(_db.adaptationProposals)
              ..where(
                (table) =>
                    table.sourceScheduleId.equals(scheduleId) &
                    table.inputFingerprint.equals(fingerprint) &
                    table.deletedAt.isNull(),
              )
              ..orderBy([(p) => OrderingTerm.desc(p.id)])
              ..limit(1))
            .getSingleOrNull();
    if (existing?.decision == AdaptationDecision.expired.name) {
      existing = null;
    }
    if (existing != null &&
        existing.decision != AdaptationDecision.proposed.name) {
      return null;
    }
    final proposal = AdaptationProposal(
      trigger: AdaptationTrigger.lowRecovery,
      weekStart: weekStart,
      reason: effectiveReason,
      changes: [
        AdaptationChange(
          scheduleId: scheduleId,
          plan: reduced,
          coveredVolume: const {},
        ),
      ],
      uncoveredVolume: const {},
      inputFingerprint: fingerprint,
    );
    final id =
        existing?.id ??
        await _db
            .into(_db.adaptationProposals)
            .insert(
              AdaptationProposalsCompanion.insert(
                programId: schedule.programId!,
                sourceScheduleId: Value(scheduleId),
                weekStartIso: _iso(weekStart),
                trigger: AdaptationTrigger.lowRecovery.name,
                reason: effectiveReason,
                inputFingerprint: fingerprint,
                proposalJson: _encode(proposal),
              ),
            );
    if (existing != null) {
      // Reopening a pending preview recalculates it against the current plan.
      // Previously the duplicate fingerprint prevented a stale preview retry.
      await (_db.update(
        _db.adaptationProposals,
      )..where((p) => p.id.equals(id))).write(
        AdaptationProposalsCompanion(
          proposalJson: Value(_encode(proposal)),
          reason: Value(proposal.reason),
        ),
      );
    }
    return StoredAdaptationProposal(
      id: id,
      proposal: proposal,
      sourceScheduleId: scheduleId,
    );
  }

  Future<void> accept(int proposalId) async {
    await _revalidateProposal(proposalId);
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.adaptationProposals,
      )..where((table) => table.id.equals(proposalId))).getSingle();
      if (row.decision == AdaptationDecision.accepted.name) {
        return;
      }
      if (row.decision != AdaptationDecision.proposed.name) {
        throw const AdaptationStaleException();
      }
      final proposal = _decode(row.proposalJson);
      final ids = {
        if (row.sourceScheduleId != null &&
            row.trigger != AdaptationTrigger.incompleteWorkout.name)
          row.sourceScheduleId!,
        for (final change in proposal.changes) change.scheduleId,
      };
      for (final id in ids) {
        final target = await (_db.select(
          _db.scheduledWorkouts,
        )..where((s) => s.id.equals(id))).getSingleOrNull();
        if (target == null ||
            target.deletedAt != null ||
            target.completedSessionId != null ||
            !const [
              ScheduleStatus.planned,
              ScheduleStatus.moved,
            ].contains(target.status)) {
          throw const AdaptationStaleException();
        }
      }
      for (final change in proposal.changes) {
        await _db
            .into(_db.adaptationOverrides)
            .insert(
              AdaptationOverridesCompanion.insert(
                proposalId: proposalId,
                scheduleId: change.scheduleId,
                planJson: change.plan.encode(),
              ),
            );
      }
      if (row.trigger == AdaptationTrigger.skippedWorkout.name &&
          row.sourceScheduleId != null) {
        await (_db.update(
          _db.scheduledWorkouts,
        )..where((table) => table.id.equals(row.sourceScheduleId!))).write(
          const ScheduledWorkoutsCompanion(
            status: Value(ScheduleStatus.skipped),
          ),
        );
      }
      await (_db.update(
        _db.adaptationProposals,
      )..where((table) => table.id.equals(proposalId))).write(
        AdaptationProposalsCompanion(
          decision: const Value('accepted'),
          decidedAt: Value(_clock.now()),
        ),
      );
    });
  }

  Future<void> decline(int proposalId, {bool skipSource = false}) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.adaptationProposals,
      )..where((table) => table.id.equals(proposalId))).getSingle();
      if (row.decision != AdaptationDecision.proposed.name) {
        return;
      }
      final source = row.sourceScheduleId == null
          ? null
          : await (_db.select(_db.scheduledWorkouts)
                  ..where((table) => table.id.equals(row.sourceScheduleId!)))
                .getSingleOrNull();
      // Only a skipped-workout proposal may mark its source as skipped. A
      // session the user actually trained (fully or partially) stays done.
      if (skipSource &&
          row.trigger == AdaptationTrigger.skippedWorkout.name &&
          source != null &&
          source.status != ScheduleStatus.done &&
          source.status != ScheduleStatus.inProgress &&
          source.completedSessionId == null) {
        await (_db.update(
          _db.scheduledWorkouts,
        )..where((table) => table.id.equals(row.sourceScheduleId!))).write(
          const ScheduledWorkoutsCompanion(
            status: Value(ScheduleStatus.skipped),
          ),
        );
      }
      await (_db.update(
        _db.adaptationProposals,
      )..where((table) => table.id.equals(proposalId))).write(
        AdaptationProposalsCompanion(
          decision: const Value('declined'),
          decidedAt: Value(_clock.now()),
        ),
      );
    });
  }

  Future<Map<String, int>> _recoveryByMuscle({DateTime? asOf}) async {
    final snapshot = await TrainingSnapshot.load(_db);
    // Health workouts are deliberately fed only into the recovery model. They
    // can make a catch-up set unsafe, but are never guessed as completed gym
    // sets or used to inflate the user's weekly volume.
    final List<HealthDataPoint> externalWorkouts = _health == null
        ? const []
        : (await _health.readWorkouts(14)).value ?? const [];
    final healthHistory = _health == null
        ? 0
        : await _health.getDaysOfStepHistory();
    final values = MuscleRecoveryV3.compute(
      snapshot: snapshot,
      asOf: asOf ?? _clock.now(),
      externalWorkouts: externalWorkouts,
      daysOfHealthHistory: healthHistory,
    );
    return {for (final value in values) value.muscle: value.recoveryScore};
  }

  Future<Map<String, double>> _actualWeekVolume(
    DateTime start,
    DateTime end,
    Map<int, List<ExerciseMuscleData>> musclesByExercise,
  ) async {
    final snapshot = await TrainingSnapshot.load(_db);
    final out = <String, double>{};
    for (final set in snapshot.sets) {
      // A session may contain planned or abandoned rows after a partial
      // workout. Only an explicitly completed, non-warmup working set earns
      // weekly-volume credit.
      if (set.set.completedAt == null || set.set.isWarmup) {
        continue;
      }
      final at = set.set.completedAt!;
      if (at.isBefore(start) ||
          !at.isBefore(DateTime(end.year, end.month, end.day + 1))) {
        continue;
      }
      for (final entry in MuscleRecoveryV3.involvementFor(
        set,
        musclesByExercise,
      )) {
        out[entry.$1] = (out[entry.$1] ?? 0) + entry.$2;
      }
    }
    return out;
  }

  Future<Set<String>> _nextWeekMuscles(
    int programId,
    DateTime nextMonday,
    PlannedSessionResolver resolver,
    Map<int, List<ExerciseMuscleData>> musclesByExercise,
    Map<int, ExerciseCatalogData> catalogById,
  ) async {
    final until = nextMonday.add(const Duration(days: 1));
    final rows =
        await (_db.select(_db.scheduledWorkouts)
              ..where(
                (table) =>
                    table.programId.equals(programId) &
                    table.deletedAt.isNull() &
                    table.status.isIn([
                      ScheduleStatus.planned,
                      ScheduleStatus.moved,
                    ]) &
                    table.dateIso.isBiggerOrEqualValue(_iso(nextMonday)) &
                    table.dateIso.isSmallerOrEqualValue(_iso(until)),
              )
              ..orderBy([(table) => OrderingTerm(expression: table.dateIso)]))
            .get();
    final result = <String>{};
    for (final row in rows) {
      final plan = await resolver.resolveProgramDay(
        row.programDayId,
        templateOverride: row.templateIdOverride,
      );
      final credit = <String, double>{};
      _addPlanVolume(credit, plan, musclesByExercise, catalogById);
      result.addAll(credit.keys);
    }
    return result;
  }

  static DateTime _monday(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: date.weekday - DateTime.monday));

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
