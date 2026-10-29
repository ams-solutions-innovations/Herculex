part of '../training_coaching_repository.dart';

extension _CoachingSafety on TrainingCoachingRepository {
  Future<Map<String, double>> _credit(PlannedSessionSnapshot plan) async {
    final result = <String, double>{};
    for (final e in plan.exercises) {
      final exercise = await (db.select(
        db.exerciseCatalog,
      )..where((c) => c.id.equals(e.exerciseId))).getSingle();
      final rows = await (db.select(
        db.exerciseMuscles,
      )..where((m) => m.exerciseId.equals(e.exerciseId))).get();
      final n = e.sets.where((s) => !s.isWarmup).length;
      if (rows.isEmpty) {
        final m =
            MuscleRecoveryV3.alias[exercise.primaryMuscle] ??
            exercise.primaryMuscle;
        result[m] = (result[m] ?? 0) + n;
      } else {
        for (final r in rows) {
          final m = MuscleRecoveryV3.alias[r.muscle] ?? r.muscle;
          final credit =
              ((MuscleRecoveryV3.roleWeight[r.role] ?? 0) * r.contribution)
                  .clamp(0.0, 1.0);
          result[m] = (result[m] ?? 0) + n * credit;
        }
      }
    }
    return result;
  }

  Future<void> _validateSafety(
    List<CoachingPlanChange> changes,
    CoachingSignal signal,
  ) async {
    final added = <String>{};
    for (final c in changes) {
      final before = await _credit(c.before), after = await _credit(c.after);
      added.addAll(after.keys.where((m) => after[m]! > (before[m] ?? 0) + .01));
      if (c.scheduleId != null) {
        final row = await (db.select(
          db.scheduledWorkouts,
        )..where((s) => s.id.equals(c.scheduleId!))).getSingleOrNull();
        if (row == null ||
            row.deletedAt != null ||
            row.completedSessionId != null ||
            !['planned', 'moved'].contains(row.status)) {
          throw StateError(
            'An affected workout has already changed or started.',
          );
        }
      }
    }
    if (added.isEmpty) return;
    if (signal.source.policy == 'do_not_catch_up')
      throw StateError(
        'Intentional fatigue or pain reductions are not replaced.',
      );
    final now = clock.now();
    final base = await TrainingSnapshot.load(
      db,
      from: now.subtract(const Duration(days: 84)),
      until: now,
    );
    final List<HealthDataPoint> external = health == null
        ? []
        : (await health!.readWorkouts(14)).value ?? [];
    final cns = CnsTrends.compute(snapshot: base, asOf: now);
    if (cns.deloadSuggested)
      throw StateError('Current fatigue signals favour a lighter schedule.');
    final deloads = MuscleDeloadAdvisor.compute(
      snapshot: base,
      externalWorkouts: external,
      asOf: now,
      cnsTrends: cns,
    );
    if (deloads.any(
      (d) => added.contains(d.muscle) && d.urgency == DeloadUrgency.recommended,
    )) {
      throw StateError(
        'A targeted muscle currently has a deload recommendation.',
      );
    }
    final joints = await JointPainRepository(db).currentStatuses();
    for (final joint in joints.values.where((j) => j.isFlagged)) {
      if ((JointModel.influencingMuscles[joint.joint] ?? {}).entries.any(
        (e) => e.value >= .5 && added.contains(e.key),
      )) {
        throw StateError(
          'The added work would load a currently flagged joint.',
        );
      }
    }
    final until = changes
        .map((c) => c.date)
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(const Duration(days: 7));
    final schedules =
        await (db.select(db.scheduledWorkouts)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.completedSessionId.isNull() &
                  s.status.isIn(['planned', 'moved']) &
                  s.dateIso.isBiggerOrEqualValue(
                    TrainingCoachingRepository.iso(now),
                  ) &
                  s.dateIso.isSmallerOrEqualValue(
                    TrainingCoachingRepository.iso(until),
                  ),
            ))
            .get();
    final timeline =
        <({DateTime at, PlannedSessionSnapshot plan, bool changed})>[];
    final resolver = PlannedSessionResolver(db, clock: clock);
    for (final s in schedules) {
      final change = changes.where((c) => c.scheduleId == s.id).firstOrNull;
      final plan = change?.after ?? await resolver.resolveScheduledWorkout(s);
      final at = change?.startsAt ?? CoachingPreviews._scheduleTime(s);
      // Untimed sessions on the same date might occur on either side of the
      // added work. Require a real time rather than assuming no conflict.
      if (s.startTimeMinutes == null &&
          change == null &&
          changes.any(
            (c) => TrainingCoachingRepository.iso(c.date) == s.dateIso,
          )) {
        final muscles = await _credit(plan);
        if (muscles.keys.any(added.contains))
          throw StateError(
            'Set a time for the other workout on this date so overlap can be checked.',
          );
      }
      if (at.isBefore(now)) continue;
      timeline.add((at: at, plan: plan, changed: change != null));
    }
    for (final c in changes.where((c) => c.scheduleId == null)) {
      timeline.add((at: c.startsAt!, plan: c.after, changed: true));
    }
    timeline.sort((a, b) => a.at.compareTo(b.at));
    final tolerances = _tolerances(base, now);
    final simulated = base.sets.toList();
    for (final item in timeline) {
      final credit = await _credit(item.plan);
      final meaningful = credit.entries
          .where((e) => e.value >= .5 && added.contains(e.key))
          .map((e) => e.key)
          .toSet();
      final snapshot = TrainingSnapshot(
        sets: simulated,
        exerciseMuscles: base.exerciseMuscles,
      );
      final recovery = MuscleRecoveryV3.compute(
        snapshot: snapshot,
        externalWorkouts: external,
        asOf: item.at,
      );
      if (recovery.any(
        (r) => meaningful.contains(r.muscle) && r.recoveryScore < 70,
      )) {
        throw StateError(
          'The projected schedule leaves too little recovery for the affected muscles.',
        );
      }
      final from = item.at.subtract(const Duration(days: 7));
      final weekly = <String, double>{};
      final byExercise = <int, List<ExerciseMuscleData>>{};
      for (final m in base.exerciseMuscles) {
        byExercise.putIfAbsent(m.exerciseId, () => []).add(m);
      }
      for (final set in simulated.where(
        (s) =>
            s.set.completedAt != null &&
            !s.set.completedAt!.isBefore(from) &&
            !s.set.completedAt!.isAfter(item.at),
      )) {
        for (final (muscle, value) in MuscleRecoveryV3.involvementFor(
          set,
          byExercise,
        )) {
          weekly[muscle] = (weekly[muscle] ?? 0) + value.clamp(0, 1);
        }
      }
      for (final m in added) {
        if ((weekly[m] ?? 0) + (credit[m] ?? 0) >
            VolumeBands.forGroup(m, tolerance: tolerances[m]).maximum) {
          throw StateError(
            'The projected seven-day volume exceeds the current volume guardrail.',
          );
        }
      }
      simulated.addAll(await _simulate(item.plan, item.at));
    }
  }

  Future<List<ResolvedSet>> _simulate(
    PlannedSessionSnapshot plan,
    DateTime at,
  ) async {
    final result = <ResolvedSet>[];
    var offset = 5 * 60;
    for (final e in plan.exercises) {
      final exercise = await (db.select(
        db.exerciseCatalog,
      )..where((c) => c.id.equals(e.exerciseId))).getSingle();
      for (final s in e.sets.where((s) => !s.isWarmup)) {
        offset += e.restSeconds + ((s.repsMax ?? 10) * 3.5).ceil();
        result.add(
          ResolvedSet(
            session: WorkoutSessionData(id: -1, startedAt: at),
            workoutExercise: e.targetExercise,
            exercise: exercise,
            set: SetEntryData(
              id: -result.length - 1,
              workoutExerciseId: -1,
              setIndex: s.index,
              weightKg: s.weightKg ?? 0,
              reps: s.repsMin ?? 0,
              rpeX10: s.rpeX10 ?? (s.rir == null ? 80 : (10 - s.rir!) * 10),
              isWarmup: false,
              isCompleted: true,
              completedAt: at.add(Duration(seconds: offset)),
              setType: s.setType,
            ),
            setType: SetType.fromId(s.setType),
            bands: [],
            accessoryNames: [],
            forearmMultiplier: 1,
          ),
        );
      }
      offset += 90;
    }
    return result;
  }

  Map<String, VolumeTolerance> _tolerances(
    TrainingSnapshot snapshot,
    DateTime now,
  ) {
    DateTime monday(DateTime d) => DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: d.weekday - 1));
    final current = monday(now);
    final muscles = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      muscles.putIfAbsent(m.exerciseId, () => []).add(m);
    }
    final volumes = <String, Map<DateTime, double>>{};
    final benchmarks = <String, Map<int, ResolvedSet>>{};
    for (final s in snapshot.sets) {
      final at = s.set.completedAt;
      if (at == null ||
          !at.isBefore(current) ||
          at.isBefore(current.subtract(const Duration(days: 56))))
        continue;
      final week = monday(at);
      for (final (muscle, credit) in MuscleRecoveryV3.involvementFor(
        s,
        muscles,
      )) {
        final weeks = volumes.putIfAbsent(muscle, () => {});
        weeks[week] = (weeks[week] ?? 0) + credit.clamp(0, 1);
      }
      if (s.set.rpeX10 == null ||
          s.setType != SetType.standard ||
          !s.metric.isRepBased)
        continue;
      final key =
          '${s.exercise.id}|${s.equipmentVariant}|${s.workoutExercise.machineConfigJson}|${s.set.weightKg}';
      final sessions = benchmarks.putIfAbsent(key, () => {});
      final previous = sessions[s.session.id];
      if (previous == null || previous.set.reps < s.set.reps)
        sessions[s.session.id] = s;
    }
    final stable = <String, Set<DateTime>>{},
        declining = <String, Set<DateTime>>{};
    for (final sessions in benchmarks.values) {
      final ordered = sessions.values.toList()
        ..sort((a, b) => a.session.startedAt.compareTo(b.session.startedAt));
      for (var i = 1; i < ordered.length; i++) {
        final a = ordered[i - 1], b = ordered[i];
        if ((a.set.rpeX10! - b.set.rpeX10!).abs() > 10) continue;
        for (final (muscle, credit) in MuscleRecoveryV3.involvementFor(
          b,
          muscles,
        )) {
          if (credit < .5) continue;
          final target = b.set.reps < a.set.reps - 1 ? declining : stable;
          target.putIfAbsent(muscle, () => {}).add(monday(b.set.completedAt!));
        }
      }
    }
    final result = <String, VolumeTolerance>{};
    for (final entry in volumes.entries) {
      final weeks =
          entry.value.keys
              .where(
                (w) =>
                    stable[entry.key]?.contains(w) == true &&
                    declining[entry.key]?.contains(w) != true,
              )
              .toList()
            ..sort();
      var sustained = 0.0;
      for (var i = 1; i < weeks.length; i++) {
        if (weeks[i].difference(weeks[i - 1]).inDays == 7) {
          sustained = math.max(
            sustained,
            math.min(entry.value[weeks[i]]!, entry.value[weeks[i - 1]]!),
          );
        }
      }
      if (sustained > 0)
        result[entry.key] = VolumeTolerance(
          weeksObserved: weeks.length,
          sustainedSets: sustained,
        );
    }
    return result;
  }
}
