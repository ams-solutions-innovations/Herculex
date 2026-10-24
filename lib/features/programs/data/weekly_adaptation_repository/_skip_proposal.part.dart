part of '../weekly_adaptation_repository.dart';

extension _SkipProposal on WeeklyAdaptationRepository {
  Future<StoredAdaptationProposal?> _propose({
    required int scheduleId,
    required AdaptationTrigger trigger,
    int? sourceSessionId,
  }) async {
    final source =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.id.equals(scheduleId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (source == null || source.programId == null) {
      return null;
    }
    if (trigger == AdaptationTrigger.skippedWorkout &&
        (!const [
              ScheduleStatus.planned,
              ScheduleStatus.moved,
            ].contains(source.status) ||
            source.completedSessionId != null)) {
      return null;
    }
    final program = await (_db.select(
      _db.programs,
    )..where((p) => p.id.equals(source.programId!))).getSingleOrNull();
    if (program == null || program.deletedAt != null || program.archived) {
      return null;
    }
    final sourceDate = DateTime.tryParse(source.dateIso);
    if (sourceDate == null) {
      return null;
    }
    final weekStart = WeeklyAdaptationRepository._monday(sourceDate);
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
    );
    final schedules =
        await (_db.select(_db.scheduledWorkouts)
              ..where(
                (t) =>
                    t.programId.equals(source.programId!) &
                    t.deletedAt.isNull() &
                    t.dateIso.isBiggerOrEqualValue(
                      WeeklyAdaptationRepository._iso(weekStart),
                    ) &
                    t.dateIso.isSmallerOrEqualValue(
                      WeeklyAdaptationRepository._iso(weekEnd),
                    ),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.dateIso),
                (t) => OrderingTerm.asc(t.orderIndex),
              ]))
            .get();
    if (schedules.isEmpty) {
      return null;
    }
    final resolver = PlannedSessionResolver(_db);
    final originalPlans = <int, PlannedSessionSnapshot>{};
    final remainingPlans = <int, PlannedSessionSnapshot>{};
    final now = _clock.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final s in schedules) {
      originalPlans[s.id] = await resolver.resolveProgramDay(
        s.programDayId,
        templateOverride: s.templateIdOverride,
      );
      final day = DateTime.parse(s.dateIso);
      if (s.id != source.id &&
          !day.isBefore(today) &&
          day.isAfter(sourceDate) &&
          const [
            ScheduleStatus.planned,
            ScheduleStatus.moved,
          ].contains(s.status) &&
          s.completedSessionId == null) {
        remainingPlans[s.id] = await resolver.resolveScheduledWorkout(s);
      }
    }
    final catalog = await _db.select(_db.exerciseCatalog).get();
    final catalogById = {for (final e in catalog) e.id: e};
    final muscleRows = await _db.select(_db.exerciseMuscles).get();
    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final row in muscleRows) {
      musclesByExercise.putIfAbsent(row.exerciseId, () => []).add(row);
    }
    final target = <String, double>{};
    for (final plan in originalPlans.values) {
      _addPlanVolume(target, plan, musclesByExercise, catalogById);
    }
    final actual = await _actualWeekVolume(
      weekStart,
      weekEnd,
      musclesByExercise,
    );
    // Reserve every remaining plan, including already accepted catch-up work.
    // Only genuinely missing weekly work is eligible for another addition.
    for (final plan in remainingPlans.values) {
      _addPlanVolume(actual, plan, musclesByExercise, catalogById);
    }
    for (final s in schedules.where(
      (s) => s.id != source.id && s.status == ScheduleStatus.inProgress,
    )) {
      final reserved = await resolver.resolveScheduledWorkout(s);
      _addPlanVolume(actual, reserved, musclesByExercise, catalogById);
    }
    final priorities = await _musclePriorities(source.programId!);
    final nextWeekConflict = await _nextWeekMuscles(
      source.programId!,
      DateTime(weekEnd.year, weekEnd.month, weekEnd.day + 1),
      resolver,
      musclesByExercise,
      catalogById,
    );
    final missedExercises = [
      ...originalPlans[source.id]!.exercises,
      for (final s in schedules.where(
        (s) => s.id != source.id && s.status == ScheduleStatus.skipped,
      ))
        ...originalPlans[s.id]!.exercises,
    ];
    final candidates = <AdaptationCandidate>[];
    final recoveryByDate = <String, Map<String, int>>{};
    for (final s in schedules.where((s) => remainingPlans.containsKey(s.id))) {
      final date = DateTime.parse(s.dateIso);
      final targetPlan = remainingPlans[s.id]!;
      final recovery = recoveryByDate[s.dateIso] ??= await _recoveryByMuscle(
        asOf: DateTime(date.year, date.month, date.day, now.hour, now.minute),
      );
      for (final exercise in missedExercises) {
        for (
          var size = 1;
          size <= math.min(2, exercise.sets.where((s) => !s.isWarmup).length);
          size++
        ) {
          final addition = _adaptedExercise(exercise, maxSets: size);
          final credit = _exerciseVolume(
            addition.exerciseId,
            addition.workingSetCount,
            musclesByExercise,
            catalogById,
          );
          if (credit.isEmpty) {
            continue;
          }
          final readiness = credit.keys
              .map((m) => recovery[m] ?? 100)
              .fold<int>(100, math.min);
          final adjacent = schedules.any((other) {
            if (other.id == s.id || !remainingPlans.containsKey(other.id)) {
              return false;
            }
            final separation = DateTime.parse(
              other.dateIso,
            ).difference(date).inDays.abs();
            if (separation >= 2) {
              return false;
            }
            final volume = <String, double>{};
            _addPlanVolume(
              volume,
              remainingPlans[other.id]!,
              musclesByExercise,
              catalogById,
            );
            return credit.keys.any(volume.containsKey);
          });
          candidates.add(
            AdaptationCandidate(
              scheduleId: s.id,
              date: date,
              plan: _adaptedPlan(targetPlan),
              addition: addition,
              muscleCredit: credit,
              recoveryScore: readiness,
              originalWorkingSets: _adaptedPlan(
                originalPlans[s.id]!,
              ).workingSetCount,
              priority: _exercisePriority(
                exercise,
                credit,
                program.trainingGoal,
                priorities,
              ),
              conflictsNextWeek:
                  adjacent ||
                  (date.isAfter(weekEnd.subtract(const Duration(days: 1))) &&
                      credit.keys.any(nextWeekConflict.contains)),
            ),
          );
        }
      }
    }
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'source': [source.id, source.status, source.completedSessionId],
              'trigger': trigger.name,
              'today': WeeklyAdaptationRepository._iso(today),
              'goal': program.trainingGoal,
              'priorities': priorities,
              'target': target,
              'actualAndReserved': actual,
              'recovery': recoveryByDate,
              'nextWeek': nextWeekConflict.toList()..sort(),
              'plans': [
                for (final s in schedules)
                  [
                    s.id,
                    s.dateIso,
                    s.status,
                    s.completedSessionId,
                    _adaptedPlan(originalPlans[s.id]!).encode(),
                    if (remainingPlans[s.id] case final plan?)
                      _adaptedPlan(plan).encode(),
                  ],
              ],
            }),
          ),
        )
        .toString();
    await _expireOtherProposals(source.id, trigger, fingerprint);
    var prior =
        await (_db.select(_db.adaptationProposals)
              ..where(
                (table) =>
                    table.sourceScheduleId.equals(source.id) &
                    table.inputFingerprint.equals(fingerprint) &
                    table.deletedAt.isNull(),
              )
              ..orderBy([(p) => OrderingTerm.desc(p.id)])
              ..limit(1))
            .getSingleOrNull();
    if (prior?.decision == AdaptationDecision.expired.name) {
      prior = null;
    }
    if (prior != null && prior.decision != AdaptationDecision.proposed.name) {
      return null;
    }

    final proposal = WeeklyAdaptationEngine.propose(
      trigger: trigger,
      weekStart: weekStart,
      targetVolume: target,
      actualVolume: actual,
      candidates: candidates,
      inputFingerprint: fingerprint,
    );
    // Do not interrupt the user after a fully completed session.
    if (!proposal.hasChanges && proposal.uncoveredVolume.isEmpty) {
      return null;
    }
    final id =
        prior?.id ??
        await _db
            .into(_db.adaptationProposals)
            .insert(
              AdaptationProposalsCompanion.insert(
                programId: source.programId!,
                sourceScheduleId: Value(source.id),
                sourceSessionId: Value(sourceSessionId),
                weekStartIso: WeeklyAdaptationRepository._iso(weekStart),
                trigger: trigger.name,
                reason: proposal.reason,
                inputFingerprint: fingerprint,
                proposalJson: _encode(proposal),
              ),
            );
    if (prior != null) {
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
      sourceScheduleId: source.id,
      exerciseNames: {for (final e in catalog) e.id: e.name},
      scheduleDates: {for (final s in schedules) s.id: s.dateIso},
    );
  }
}
