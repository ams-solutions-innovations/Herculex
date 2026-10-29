part of '../training_coaching_repository.dart';

extension CoachingPreviews on TrainingCoachingRepository {
  Future<CoachingPreview> _preview(
    int proposalId, {
    int availableMinutes = 30,
    DateTime? extraAt,
  }) async {
    if (availableMinutes < 5 || availableMinutes > 180)
      throw StateError('Choose between 5 and 180 available minutes.');
    final row = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(proposalId))).getSingle();
    if (row.status != 'proposed' || row.deletedAt != null)
      throw StateError('This suggestion is no longer available.');
    if (row.programId == null)
      throw StateError(
        'Link these workouts to a program before applying a program change.',
      );
    await _requireNoOtherTrial(row);
    final s = signal(row);
    if (extraAt != null && s.kind != CoachingKind.catchUp)
      throw StateError(
        'Optional workouts are only offered for work missed because of time.',
      );
    final context = row.sourceSessionId == null
        ? const ReportContext()
        : await WorkoutReportRepository(
            db,
            clock,
          ).contextFor(row.sourceSessionId!);
    if (context.pain == true || context.reason == ReportReason.pain) {
      throw StateError(
        'You reported pain. Review that first; this suggestion will not prescribe replacement work.',
      );
    }
    if (s.source.policy == 'do_not_catch_up' &&
        s.kind != CoachingKind.reduceSets) {
      throw StateError(
        'This work was intentionally reduced. Additional work is not proposed.',
      );
    }
    final now = clock.now();
    final schedules =
        await (db.select(db.scheduledWorkouts)
              ..where(
                (w) =>
                    w.programId.equals(row.programId!) &
                    w.deletedAt.isNull() &
                    w.completedSessionId.isNull() &
                    w.status.isIn(['planned', 'moved']) &
                    w.dateIso.isBiggerOrEqualValue(
                      TrainingCoachingRepository.iso(now),
                    ) &
                    w.dateIso.isSmallerOrEqualValue(
                      TrainingCoachingRepository.iso(
                        now.add(const Duration(days: 28)),
                      ),
                    ),
              )
              ..orderBy([
                (w) => OrderingTerm.asc(w.dateIso),
                (w) => OrderingTerm.asc(w.orderIndex),
              ]))
            .get();
    final changes = <CoachingPlanChange>[];
    final missing = s.kind == CoachingKind.catchUp
        ? await _missingWork(row, s)
        : <PlannedExerciseSnapshot>[];
    final remaining = missing.toList();
    final resolver = PlannedSessionResolver(db, clock: clock);
    for (final schedule in schedules) {
      final at = _scheduleTime(schedule);
      if (at.isBefore(now) || schedule.programDayId == null) continue;
      final day = await (db.select(
        db.programDays,
      )..where((d) => d.id.equals(schedule.programDayId!))).getSingle();
      final week = await (db.select(
        db.programWeeks,
      )..where((w) => w.id.equals(day.programWeekId))).getSingle();
      final program = await (db.select(
        db.programs,
      )..where((p) => p.id.equals(row.programId!))).getSingle();
      if (program.archived ||
          Periodization.isPlannedDeload(
            model: PeriodizationModel.fromId(program.periodizationModel),
            totalWeeks: program.weeks,
            weekIndex: week.weekIndex,
          ))
        continue;
      final dayKey =
          '${day.cycleDayIndex ?? day.dayOfWeek}|${day.slotLabel ?? day.name}';
      if (s.kind != CoachingKind.catchUp && dayKey != s.source.day) continue;
      if (s.source.data['phase'] != null &&
          (week.blockPhase ?? program.periodizationModel) !=
              s.source.data['phase'])
        continue;
      final current = await resolver.resolveScheduledWorkout(schedule);
      final exercises = current.exercises.toList();
      if (s.kind == CoachingKind.catchUp) {
        if (extraAt != null) break;
        if (at.isAfter(now.add(const Duration(days: 7)))) continue;
        final budget = math.min(4, (_working(current) * .2).floor());
        var added = 0;
        final additions = _fitWorkUnits(remaining, current, budget: budget);
        exercises.addAll(additions);
        added = additions.fold<int>(
          0,
          (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
        );
        if (added == 0) continue;
      } else {
        final target = s.exercise == null
            ? -1
            : await _indexFor(exercises, s.exercise!);
        switch (s.kind) {
          case CoachingKind.reduceSets:
            if (target < 0) continue;
            final e = exercises[target];
            final count = s.targetSets!;
            if (e.sets.where((s) => !s.isWarmup).length <= count) continue;
            var working = 0;
            exercises[target] = copyPlannedExercise(
              e,
              sets: e.sets
                  .where((set) => set.isWarmup || working++ < count)
                  .toList(),
            );
          case CoachingKind.exerciseOrder:
            if (target < 0 || exercises[target].supersetGroup != null) continue;
            final firstAccessory = exercises.indexWhere(
              (e) =>
                  ['accessory', 'isolation'].contains(e.slotRole) &&
                  e.supersetGroup == null,
            );
            if (firstAccessory < 0 ||
                target <= firstAccessory ||
                ![
                  'accessory',
                  'isolation',
                ].contains(exercises[target].slotRole))
              continue;
            final e = exercises.removeAt(target);
            exercises.insert(firstAccessory, e);
          case CoachingKind.equipment:
            if (target < 0) continue;
            final replacement = await _fromObserved(
              s.replacement!,
              order: exercises[target].orderIndex,
            );
            // A replacement uses its own targets; no absolute load is copied.
            exercises[target] = replacement;
          case CoachingKind.goalGap:
            final adjusted = await _goalExercises(current, s);
            exercises.clear();
            exercises.addAll(adjusted);
          case CoachingKind.shorterWorkout:
            while (_minutes(
                  PlannedSessionSnapshot(
                    name: current.name,
                    exercises: exercises,
                  ),
                ) >
                availableMinutes) {
              final index = exercises.lastIndexWhere(
                (e) =>
                    ['accessory', 'isolation'].contains(e.slotRole) &&
                    e.supersetGroup == null &&
                    e.sets.any((s) => !s.isWarmup),
              );
              if (index < 0) break;
              final e = exercises[index];
              final sets = e.sets.toList();
              sets.removeAt(sets.lastIndexWhere((s) => !s.isWarmup));
              if (!sets.any((s) => !s.isWarmup)) {
                exercises.removeAt(index);
              } else {
                exercises[index] = copyPlannedExercise(e, sets: sets);
              }
            }
          case CoachingKind.catchUp:
            break;
        }
      }
      final after = PlannedSessionSnapshot(
        name: current.name,
        exercises: [
          for (var i = 0; i < exercises.length; i++)
            copyPlannedExercise(exercises[i], orderIndex: i),
        ],
      );
      if (await codec.encode(after) == await codec.encode(current)) continue;
      if (s.kind == CoachingKind.shorterWorkout &&
          _minutes(after) > availableMinutes)
        continue;
      final candidate = CoachingPlanChange(
        date: DateTime.parse(schedule.dateIso),
        startsAt: at,
        scheduleId: schedule.id,
        before: current,
        after: after,
      );
      try {
        await _validateSafety([...changes, candidate], s);
      } on StateError {
        continue;
      }
      changes.add(candidate);
      if (s.kind == CoachingKind.catchUp) {
        final oldCount = current.exercises.length;
        for (final e in after.exercises.skip(oldCount)) {
          remaining.removeWhere(
            (r) =>
                r.exerciseId == e.exerciseId && r.sets.length == e.sets.length,
          );
        }
        if (remaining.isEmpty) break;
      } else if (changes.length >= 2) {
        break;
      }
    }
    if (s.kind == CoachingKind.catchUp && extraAt != null) {
      if (extraAt.isBefore(now) ||
          extraAt.isAfter(now.add(const Duration(days: 7)))) {
        throw StateError('Choose a future time within the next seven days.');
      }
      final extras =
          await (db.select(db.scheduledWorkouts)..where(
                (w) =>
                    w.oneOffPlanJson.isNotNull() &
                    w.deletedAt.isNull() &
                    w.status.isNotIn(['skipped']) &
                    w.dateIso.isBiggerOrEqualValue(
                      TrainingCoachingRepository.iso(
                        extraAt.subtract(const Duration(days: 6)),
                      ),
                    ) &
                    w.dateIso.isSmallerOrEqualValue(
                      TrainingCoachingRepository.iso(
                        extraAt.add(const Duration(days: 6)),
                      ),
                    ),
              ))
              .get();
      if (extras.isNotEmpty)
        throw StateError(
          'An optional workout is already scheduled within this seven-day window.',
        );
      final chosen = _fitWorkUnits(
        remaining,
        const PlannedSessionSnapshot(name: 'Optional workout', exercises: []),
        availableMinutes: availableMinutes,
      );
      if (chosen.isNotEmpty)
        changes.add(
          CoachingPlanChange(
            date: extraAt,
            startsAt: extraAt,
            before: const PlannedSessionSnapshot(
              name: 'Rest / free time',
              exercises: [],
            ),
            after: PlannedSessionSnapshot(
              name: await _catchUpName(chosen),
              exercises: [
                for (var i = 0; i < chosen.length; i++)
                  copyPlannedExercise(chosen[i], orderIndex: i),
              ],
            ),
          ),
        );
    }
    if (changes.isEmpty)
      throw StateError(
        s.kind == CoachingKind.catchUp
            ? 'No safe redistribution fits existing workouts. You can review an optional short workout at a time you choose.'
            : 'No suitable future workout fits this change. The main lifts and recovery constraints remain protected.',
      );
    await _validateSafety(changes, s);
    final evidence = await _evidenceFingerprint(s);
    final names = <int, String>{};
    for (final change in changes) {
      for (final e in [...change.before.exercises, ...change.after.exercises]) {
        names[e.exerciseId] = (await (db.select(
          db.exerciseCatalog,
        )..where((c) => c.id.equals(e.exerciseId))).getSingle()).name;
      }
    }
    return CoachingPreview(
      proposalId: proposalId,
      signal: s,
      changes: [for (final c in changes) await _summarize(c)],
      fingerprint: await _previewFingerprint(changes, evidence),
      evidenceFingerprint: evidence,
      exerciseNames: names,
      availableMinutes: availableMinutes,
      extraAt: extraAt,
    );
  }

  Future<int> _indexFor(
    List<PlannedExerciseSnapshot> exercises,
    Map<String, dynamic> observed,
  ) async {
    for (var i = 0; i < exercises.length; i++) {
      final e = exercises[i];
      if (observed['slot'] != null &&
          await codec.slotRef(e.programExerciseSlotId) == observed['slot'])
        return i;
      if (observed['slot'] == null &&
          await codec.exerciseRef(e.exerciseId) == observed['exercise'] &&
          e.trainingMethod == observed['method'])
        return i;
    }
    return -1;
  }

  Future<PlannedExerciseSnapshot> _fromObserved(
    Map<String, dynamic> o, {
    required int order,
  }) async {
    final id = await codec.exerciseId(o['exercise'] as String);
    final catalog = await (db.select(
      db.exerciseCatalog,
    )..where((e) => e.id.equals(id))).getSingle();
    final repBased = effectiveLoggingMetric(
      exercise: catalog,
      equipmentVariant: o['variant'] as String?,
    ).isRepBased;
    final sets = (o['sets'] as List).cast<Map>();
    if (sets.any((s) => s['type'] != 'standard')) {
      throw StateError(
        'This exercise needs a custom advanced prescription. Review it in the program editor.',
      );
    }
    return PlannedExerciseSnapshot(
      exerciseId: id,
      orderIndex: order,
      restSeconds: o['rest'] as int? ?? 90,
      slotRole: o['role'] as String? ?? 'accessory',
      trainingMethod: 'straight_sets',
      why: 'Trial based on your repeated exercise choice.',
      equipmentVariant: o['variant'] as String?,
      allowsAdvancedTechniques: false,
      sets: [
        for (var i = 0; i < sets.length; i++)
          PlannedSetSnapshot(
            index: i + 1,
            repsMin: sets[i]['min'] as int? ?? sets[i]['reps'] as int,
            repsMax: sets[i]['max'] as int? ?? sets[i]['reps'] as int,
            isWarmup: false,
            setType: 'standard',
            intent: repBased ? 'rir2' : 'technical',
            rir: repBased ? 2 : 5,
            setTypeMetaJson:
                sets[i]['duration'] == null &&
                    sets[i]['distance'] == null &&
                    sets[i]['calories'] == null
                ? null
                : jsonEncode({
                    'setPrescription': {
                      'version': 1,
                      'targetDurationSeconds': sets[i]['duration'],
                      'targetDistanceM': sets[i]['distance'],
                      'targetCalories': sets[i]['calories'],
                    },
                  }),
          ),
      ],
    );
  }

  Future<List<PlannedExerciseSnapshot>> _missingWork(
    TrainingCoachingProposalData row,
    CoachingSignal s,
  ) async {
    if (s.source.policy != 'time')
      throw StateError(
        'Confirm a time constraint before redistributing omitted work.',
      );
    final source =
        await (db.select(db.scheduledWorkouts)
              ..where((w) => w.completedSessionId.equals(row.sourceSessionId!)))
            .getSingleOrNull();
    if (source == null)
      throw StateError('The original program occurrence is unavailable.');
    final accepted =
        await (db.select(db.adaptationProposals)..where(
              (p) =>
                  p.decision.equals('accepted') &
                  p.deletedAt.isNull() &
                  (p.sourceSessionId.equals(row.sourceSessionId!) |
                      p.sourceScheduleId.equals(source.id)),
            ))
            .get();
    if (accepted.isNotEmpty)
      throw StateError(
        'You already accepted a redistribution for this workout. Review that plan before adding more work.',
      );
    final original = await PlannedSessionResolver(
      db,
      clock: clock,
    ).resolveScheduledWorkout(source);
    final transferableGroups = await _transferableGroups(original, s.source);
    final missing = <PlannedExerciseSnapshot>[];
    for (final p in s.source.original) {
      final actual = s.source.actualFor(p);
      if (actual != null && actual['exercise'] != p['exercise']) continue;
      final done = actual?['completed'] as int? ?? 0;
      if (done >= (p['planned'] as int)) continue;
      final index = await _indexFor(original.exercises, p);
      if (index < 0)
        throw StateError(
          'The original prescription changed. Review your current program.',
        );
      final e = original.exercises[index];
      final working = e.sets.where((set) => !set.isWarmup).toList();
      if (working.length != p['planned'])
        throw StateError(
          'The original prescription changed. Reopen the program.',
        );
      if (e.trainingMethod == 'max_effort' || (e.supersetGroup != null && !transferableGroups.contains(e.supersetGroup))) continue;
      missing.add(copyPlannedExercise(e, sets: working.skip(done).toList()));
    }
    return missing;
  }

  Future<String> _evidenceFingerprint(CoachingSignal s) async {
    final sessions =
        await (db.select(db.workoutSessions)..where(
              (r) =>
                  r.syncUuid.isIn(s.evidence) &
                  r.deletedAt.isNull() &
                  r.endedAt.isNotNull(),
            ))
            .get();
    if (sessions.length != s.evidence.length)
      throw StateError('The training history changed. Reopen the suggestion.');
    final snapshots =
        await (db.select(db.workoutBehaviorSnapshots)
              ..where(
                (r) =>
                    r.sessionId.isIn(sessions.map((e) => e.id)) &
                    r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.syncUuid)]))
            .get();
    if (snapshots.any(
      (r) => !CoachingObservation.decode(r.snapshotJson).reliable,
    ))
      throw StateError(
        'This history was corrected or is no longer comparable.',
      );
    return TrainingCoachingRepository.hash(
      snapshots.map((s) => s.snapshotJson).toList(),
    );
  }

  Future<String> _previewFingerprint(
    List<CoachingPlanChange> changes,
    String evidence,
  ) async => TrainingCoachingRepository.hash({
    'evidence': evidence,
    'plans': [
      for (final c in changes)
        {
          'schedule': c.scheduleId == null
              ? null
              : (await (db.select(
                      db.scheduledWorkouts,
                    )..where((s) => s.id.equals(c.scheduleId!))).getSingle())
                    .syncUuid,
          'date': c.startsAt?.toIso8601String(),
          'before': await codec.encode(c.before),
          'after': await codec.encode(c.after),
        },
    ],
  });

  static int _working(PlannedSessionSnapshot p) => p.exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
  );
  static int _minutes(PlannedSessionSnapshot p) {
    final durations = <Duration>[];
    for (final e in p.exercises) {
      final working = e.sets.where((s) => !s.isWarmup).toList();
      var seconds = 0;
      for (final set in working) {
        Map<String, dynamic> meta = {};
        if (set.setTypeMetaJson != null) {
          final raw = jsonDecode(set.setTypeMetaJson!) as Map;
          meta = Map<String, dynamic>.from(
            raw['setPrescription'] as Map? ?? raw,
          );
        }
        final duration =
            (meta['targetDurationSeconds'] as num?)?.toInt() ??
            CalisthenicsSetPlan.decode(set.setTypeMetaJson)?.durationSeconds;
        if (duration != null) {
          seconds += duration + e.restSeconds;
        } else {
          // Distance/calorie work without a known duration cannot safely fit
          // a time budget. Ask for a manually authored prescription instead.
          if (meta['targetDistanceM'] != null ||
              meta['targetCalories'] != null) {
            throw StateError(
              'Add a duration target for distance or calorie work before using a timed suggestion.',
            );
          }
          seconds += WorkoutDurationEstimator.estimateExercise(
            workingSets: 1,
            repsMin: set.repsMin ?? 8,
            repsMax: set.repsMax ?? 12,
            restSeconds: e.restSeconds,
            setType: SetType.fromId(set.setType),
          ).inSeconds;
        }
      }
      seconds += e.sets
          .where((s) => s.isWarmup)
          .fold<int>(
            0,
            (n, s) => n + ((s.repsMax ?? s.repsMin ?? 5) * 3.5 + 30).ceil(),
          );
      durations.add(Duration(seconds: seconds));
    }
    return (WorkoutDurationEstimator.estimateSession(durations).inSeconds / 60)
            .ceil() +
        (p.exercises.isEmpty ? 0 : 5);
  }

  static DateTime _scheduleTime(ScheduledWorkoutData s) {
    final date = DateTime.parse(s.dateIso);
    return date.add(Duration(minutes: s.startTimeMinutes ?? 0));
  }

  Future<String> _catchUpName(List<PlannedExerciseSnapshot> exercises) async {
    final muscles = <String>{};
    for (final e in exercises) {
      final catalog = await (db.select(
        db.exerciseCatalog,
      )..where((c) => c.id.equals(e.exerciseId))).getSingle();
      muscles.add(
        MuscleRecoveryV3.alias[catalog.primaryMuscle] ?? catalog.primaryMuscle,
      );
    }
    if (muscles.every({'Biceps', 'Triceps', 'Forearms'}.contains))
      return 'Optional arms';
    if (muscles.every(
      {'Back', 'Lats', 'Biceps', 'Rear Delts', 'Traps', 'Forearms'}.contains,
    ))
      return 'Optional pull';
    if (muscles.every(
      {'Chest', 'Front Delts', 'Side Delts', 'Triceps'}.contains,
    ))
      return 'Optional push';
    if (muscles.every(
      {
        'Quads',
        'Hamstrings',
        'Glutes',
        'Calves',
        'Adductors',
        'Abductors',
      }.contains,
    ))
      return 'Optional lower body';
    if (muscles.every({'Abs', 'Obliques'}.contains)) return 'Optional core';
    return 'Optional catch-up';
  }
}
