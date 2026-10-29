part of '../training_coaching_repository.dart';

extension CoachingActions on TrainingCoachingRepository {
  Future<void> _accept(CoachingPreview reviewed) async {
    if (reviewed.permanent) {
      await _keep(reviewed);
      return;
    }
    final fresh = await preview(
      reviewed.proposalId,
      availableMinutes: reviewed.availableMinutes,
      extraAt: reviewed.extraAt,
    );
    if (fresh.fingerprint != reviewed.fingerprint)
      throw StateError('The evidence or plan changed. Review a fresh preview.');
    await db.transaction(() async {
      // Recheck inside the write transaction, including the global safety rules.
      final checked = await preview(
        reviewed.proposalId,
        availableMinutes: reviewed.availableMinutes,
        extraAt: reviewed.extraAt,
      );
      if (checked.fingerprint != reviewed.fingerprint)
        throw StateError('The plan changed while confirming.');
      final row = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(reviewed.proposalId))).getSingle();
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.payloadJson) as Map,
      );
      final adjusts = payload['adjusts'] as String?;
      if (adjusts != null) {
        final previous = await (db.select(
          db.trainingCoachingProposals,
        )..where((p) => p.syncUuid.equals(adjusts))).getSingleOrNull();
        if (previous != null) await cancelTrial(previous.id);
      }
      final occurrences = <Map<String, Object?>>[];
      for (final change in checked.changes) {
        var scheduleId = change.scheduleId;
        if (scheduleId == null) {
          scheduleId = await db
              .into(db.scheduledWorkouts)
              .insert(
                ScheduledWorkoutsCompanion.insert(
                  dateIso: TrainingCoachingRepository.iso(change.date),
                  programId: Value(row.programId),
                  oneOffPlanJson: Value(await codec.encode(change.after)),
                  startTimeMinutes: Value(
                    change.startsAt!.hour * 60 + change.startsAt!.minute,
                  ),
                ),
              );
        }
        final schedule = await (db.select(
          db.scheduledWorkouts,
        )..where((s) => s.id.equals(scheduleId!))).getSingle();
        final before = await codec.encode(change.before),
            after = await codec.encode(change.after);
        await db
            .into(db.trainingCoachingOverrides)
            .insert(
              TrainingCoachingOverridesCompanion.insert(
                proposalId: row.id,
                scheduleId: scheduleId,
                planJson: after,
                originalPlanJson: before,
              ),
            );
        occurrences.add({
          'schedule': schedule.syncUuid,
          'before': before,
          'after': after,
          'date': schedule.dateIso,
        });
      }
      payload['trial'] = {
        'occurrences': occurrences,
        'availableMinutes': reviewed.availableMinutes,
        'evidence': checked.evidenceFingerprint,
        'startedAt': clock.now().toUtc().toIso8601String(),
      };
      await (db.update(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(row.id))).write(
        TrainingCoachingProposalsCompanion(
          status: Value(checked.signal.oneOff ? 'kept' : 'trial'),
          payloadJson: Value(jsonEncode(payload)),
          decidedAt: Value(clock.now()),
          expiresAt: Value(
            clock.now().add(Duration(days: checked.signal.oneOff ? 7 : 28)),
          ),
        ),
      );
    });
  }

  Future<void> _cancelTrial(int id) => db.transaction(() async {
    final row = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(id))).getSingle();
    if (!['trial', 'review'].contains(row.status)) return;
    final overrides = await (db.select(
      db.trainingCoachingOverrides,
    )..where((o) => o.proposalId.equals(id) & o.deletedAt.isNull())).get();
    for (final o in overrides) {
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(o.scheduleId))).getSingleOrNull();
      if (schedule?.completedSessionId == null)
        await (db.update(
          db.trainingCoachingOverrides,
        )..where((r) => r.id.equals(o.id))).write(
          TrainingCoachingOverridesCompanion(deletedAt: Value(clock.now())),
        );
    }
    await _status(id, 'cancelled');
  });

  Future<void> _evaluate(TrainingCoachingProposalData row) async {
    final overrides = await (db.select(
      db.trainingCoachingOverrides,
    )..where((o) => o.proposalId.equals(row.id) & o.deletedAt.isNull())).get();
    final trained = <WorkoutSessionData>[];
    var met = 0;
    final minutes = <int>[];
    for (final o in overrides) {
      final schedule =
          await (db.select(
                db.scheduledWorkouts,
              )..where((s) => s.id.equals(o.scheduleId) & s.deletedAt.isNull()))
              .getSingleOrNull();
      if (schedule?.completedSessionId == null) continue;
      final session =
          await (db.select(db.workoutSessions)..where(
                (s) =>
                    s.id.equals(schedule!.completedSessionId!) &
                    s.deletedAt.isNull() &
                    s.endedAt.isNotNull(),
              ))
              .getSingleOrNull();
      if (session == null) continue;
      final snapshot =
          await (db.select(db.workoutBehaviorSnapshots)..where(
                (s) => s.sessionId.equals(session.id) & s.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (snapshot != null) {
        final actual = CoachingObservation.decode(snapshot.snapshotJson);
        final plan = await codec.decode(o.planJson);
        if (actual.data['known'] != true ||
            actual.data['corrected'] == true ||
            actual.original.length != plan.exercises.length)
          continue;
        var comparable = true;
        for (final e in plan.exercises) {
          final ref = await codec.exerciseRef(e.exerciseId);
          final catalog = await (db.select(
            db.exerciseCatalog,
          )..where((c) => c.id.equals(e.exerciseId))).getSingle();
          final captured = actual.original.where(
            (p) =>
                p['exercise'] == ref &&
                p['variant'] == (e.equipmentVariant ?? catalog.modality),
          );
          if (captured.isEmpty ||
              captured.first['planned'] !=
                  e.sets.where((s) => !s.isWarmup).length)
            comparable = false;
        }
        if (!comparable) continue;
        trained.add(session);
        minutes.add(session.endedAt!.difference(session.startedAt).inMinutes);

        if (actual.actual.fold<int>(0, (n, e) => n + (e['completed'] as int)) >=
            CoachingPreviews._working(plan))
          met++;
      }
    }
    final expired =
        row.expiresAt != null && !row.expiresAt!.isAfter(clock.now());
    if (trained.length < 2 && !expired) return;
    final payload = Map<String, dynamic>.from(
      jsonDecode(row.payloadJson) as Map,
    );
    // Report performance findings already implement equipment/load/effort
    // comparability. Reuse them instead of comparing incomparable tonnage.
    var benchmarks = 0, declines = 0;
    for (final session in trained) {
      final report = await WorkoutReportRepository(
        db,
        clock,
      ).generate(session.id);
      if (report == null) continue;
      if (report.findings.any(
        (f) => [
          'PERFORMANCE-UP',
          'PROGRESSION-PLATEAU-02',
          'PERFORMANCE-DOWN',
          'PERFORMANCE-REPEATED',
        ].contains(f.ruleId),
      ))
        benchmarks++;
      if (report.hasPerformanceDecline) declines++;
    }
    payload['result'] = {
      'completed': trained.length,
      'targetMet': met,
      'minutes': minutes,
      'comparableBenchmarks': benchmarks,
      'declines': declines,
      'conclusion': trained.length < 2 || benchmarks < 2
          ? 'insufficient'
          : declines > 0
          ? 'review'
          : met == trained.length
          ? 'manageable'
          : 'review',
    };
    await (db.update(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(row.id))).write(
      TrainingCoachingProposalsCompanion(
        status: const Value('review'),
        payloadJson: Value(jsonEncode(payload)),
      ),
    );
  }

  Future<CoachingPreview> _permanentPreview(int id) async {
    final row = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(id))).getSingle();
    if (row.status != 'review' || row.programId == null)
      throw StateError('Finish the trial before keeping this change.');
    await _requireNoOtherTrial(row);
    final localFeedback = await feedback(id);
    if (localFeedback?.pain == true)
      throw StateError(
        'You reported pain during the trial. Review the provoking movement before keeping this prescription.',
      );
    final payload = jsonDecode(row.payloadJson) as Map;
    final s = signal(row);
    final minutes = (payload['trial'] as Map)['availableMinutes'] as int;
    final schedules =
        await (db.select(db.scheduledWorkouts)
              ..where(
                (w) =>
                    w.programId.equals(row.programId!) &
                    w.programDayId.isNotNull() &
                    w.deletedAt.isNull() &
                    w.completedSessionId.isNull() &
                    w.status.isIn(['planned', 'moved']) &
                    w.dateIso.isBiggerOrEqualValue(
                      TrainingCoachingRepository.iso(clock.now()),
                    ),
              )
              ..orderBy([(w) => OrderingTerm.asc(w.dateIso)]))
            .get();
    final changes = <CoachingPlanChange>[];
    for (final schedule in schedules) {
      final day = await (db.select(
        db.programDays,
      )..where((d) => d.id.equals(schedule.programDayId!))).getSingle();
      final week = await (db.select(
        db.programWeeks,
      )..where((w) => w.id.equals(day.programWeekId))).getSingle();
      final program = await (db.select(
        db.programs,
      )..where((p) => p.id.equals(week.programId))).getSingle();
      if (Periodization.isPlannedDeload(
        model: PeriodizationModel.fromId(program.periodizationModel),
        totalWeeks: program.weeks,
        weekIndex: week.weekIndex,
      ))
        continue;
      if ('${day.cycleDayIndex ?? day.dayOfWeek}|${day.slotLabel ?? day.name}' !=
          s.source.day)
        continue;
      final before = await PlannedSessionResolver(db, clock: clock)
          .resolveProgramDay(
            day.id,
            templateOverride: schedule.templateIdOverride,
          );
      final after = await _permanentPatch(before, s, minutes);
      if (await codec.encode(before) == await codec.encode(after)) continue;
      changes.add(
        CoachingPlanChange(
          scheduleId: schedule.id,
          date: DateTime.parse(schedule.dateIso),
          startsAt: CoachingPreviews._scheduleTime(schedule),
          before: before,
          after: after,
        ),
      );
    }
    if (changes.isEmpty)
      throw StateError('There are no future program occurrences to change.');
    await _validateSafety(changes, s);
    final evidence = TrainingCoachingRepository.hash(row.payloadJson);
    final names = <int, String>{};
    for (final c in changes) {
      for (final e in [...c.before.exercises, ...c.after.exercises]) {
        names[e.exerciseId] = (await (db.select(
          db.exerciseCatalog,
        )..where((r) => r.id.equals(e.exerciseId))).getSingle()).name;
      }
    }
    return CoachingPreview(
      proposalId: id,
      signal: s,
      changes: [for (final c in changes) await _summarize(c)],
      fingerprint: await _previewFingerprint(changes, evidence),
      evidenceFingerprint: evidence,
      exerciseNames: names,
      availableMinutes: minutes,
      permanent: true,
    );
  }

  Future<PlannedSessionSnapshot> _permanentPatch(
    PlannedSessionSnapshot plan,
    CoachingSignal s,
    int minutes,
  ) async {
    final list = plan.exercises.toList();
    final index = s.exercise == null ? -1 : await _indexFor(list, s.exercise!);
    switch (s.kind) {
      case CoachingKind.reduceSets:
        if (index >= 0) {
          var n = 0;
          list[index] = copyPlannedExercise(
            list[index],
            sets: list[index].sets
                .where((e) => e.isWarmup || n++ < s.targetSets!)
                .toList(),
          );
        }
      case CoachingKind.goalGap:
        final adjusted = await _goalExercises(plan, s);
        list.clear();
        list.addAll(adjusted);
      case CoachingKind.equipment:
        if (index >= 0)
          list[index] = await _fromObserved(s.replacement!, order: index);
      case CoachingKind.exerciseOrder:
        final first = list.indexWhere(
          (e) =>
              ['accessory', 'isolation'].contains(e.slotRole) &&
              e.supersetGroup == null,
        );
        if (index > first && first >= 0 && list[index].supersetGroup == null)
          list.insert(first, list.removeAt(index));
      case CoachingKind.shorterWorkout:
        while (CoachingPreviews._minutes(
              PlannedSessionSnapshot(name: plan.name, exercises: list),
            ) >
            minutes) {
          final last = list.lastIndexWhere(
            (e) =>
                ['accessory', 'isolation'].contains(e.slotRole) &&
                e.supersetGroup == null,
          );
          if (last < 0) break;
          final sets = list[last].sets.toList();
          final working = sets.lastIndexWhere((s) => !s.isWarmup);
          if (working < 0) {
            list.removeAt(last);
            continue;
          }
          sets.removeAt(working);
          if (sets.any((s) => !s.isWarmup)) {
            list[last] = copyPlannedExercise(list[last], sets: sets);
          } else {
            list.removeAt(last);
          }
        }
      case CoachingKind.catchUp:
        throw StateError(
          'One-time catch-up workouts do not change the recurring program.',
        );
    }
    return PlannedSessionSnapshot(
      name: plan.name,
      exercises: [
        for (var i = 0; i < list.length; i++)
          copyPlannedExercise(list[i], orderIndex: i),
      ],
    );
  }

  Future<void> _keep(CoachingPreview reviewed) async {
    final fresh = await permanentPreview(reviewed.proposalId);
    if (fresh.fingerprint != reviewed.fingerprint)
      throw StateError(
        'The program changed. Review the permanent change again.',
      );
    await db.transaction(() async {
      final checked = await permanentPreview(reviewed.proposalId);
      if (checked.fingerprint != reviewed.fingerprint)
        throw StateError('The program changed while confirming.');
      final days = <int>{};
      for (final c in checked.changes) {
        final schedule = await (db.select(
          db.scheduledWorkouts,
        )..where((s) => s.id.equals(c.scheduleId!))).getSingle();
        if (!days.add(schedule.programDayId!)) continue;
        await _persistDay(schedule.programDayId!, c.after);
      }
      // The recurring blueprint now owns the change. Drop only future trial
      // overrides; completed sessions keep their immutable prescribed values.
      await cancelTrial(reviewed.proposalId);
      await _status(reviewed.proposalId, 'kept');
    });
  }
}
