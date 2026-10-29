part of '../training_coaching_repository.dart';

extension _CoachingPlanning on TrainingCoachingRepository {
  Future<List<PlannedExerciseSnapshot>> _goalExercises(
    PlannedSessionSnapshot plan,
    CoachingSignal signal,
  ) async {
    final list = plan.exercises.toList();
    final addition = await _fromObserved(
      signal.replacement!,
      order: list.length,
    );
    if (list.any((e) => e.exerciseId == addition.exerciseId)) return list;
    final desired = math.min(4, addition.sets.length);
    final growth = math.min(4, (CoachingPreviews._working(plan) * .2).floor());
    var freed = 0;
    final priorities = <String>{};
    final profile =
        await (db.select(db.physiqueProgrammingProfiles)
              ..where((p) => p.active.equals(true) & p.deletedAt.isNull())
              ..orderBy([(p) => OrderingTerm.desc(p.confirmedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (profile != null) {
      final json = jsonDecode(profile.prioritiesJson) as Map;
      for (final p in (json['musclePriorities'] as List? ?? []).cast<Map>()) {
        if (p['priority'] == 'high')
          priorities.add('${p['muscleId']}'.replaceAll('_', '').toLowerCase());
      }
    }
    // Reallocate small amounts of optional work before increasing total work.
    // Main lifts, supersets and other confirmed priorities remain intact.
    for (var i = list.length - 1; i >= 0 && freed + growth < desired; i--) {
      final e = list[i];
      if (!['accessory', 'isolation'].contains(e.slotRole) ||
          e.supersetGroup != null)
        continue;
      final catalog = await (db.select(
        db.exerciseCatalog,
      )..where((c) => c.id.equals(e.exerciseId))).getSingle();
      if (priorities.contains(
        catalog.primaryMuscle.toLowerCase().replaceAll(' ', ''),
      ))
        continue;
      final sets = e.sets.toList();
      while (sets.where((s) => !s.isWarmup).length > 1 &&
          freed + growth < desired) {
        sets.removeAt(sets.lastIndexWhere((s) => !s.isWarmup));
        freed++;
      }
      list[i] = copyPlannedExercise(e, sets: sets);
    }
    final count = math.min(desired, freed + growth);
    if (count > 0)
      list.add(
        copyPlannedExercise(addition, sets: addition.sets.take(count).toList()),
      );
    return list;
  }

  Future<CoachingPlanChange> _summarize(CoachingPlanChange change) async {
    int? estimate(PlannedSessionSnapshot p) {
      try {
        return CoachingPreviews._minutes(p);
      } on StateError {
        return null;
      }
    }

    return CoachingPlanChange(
      date: change.date,
      before: change.before,
      after: change.after,
      scheduleId: change.scheduleId,
      startsAt: change.startsAt,
      beforeVolume: await _credit(change.before),
      afterVolume: await _credit(change.after),
      beforeMinutes: estimate(change.before),
      afterMinutes: estimate(change.after),
    );
  }

  Future<Set<int>> _transferableGroups(
    PlannedSessionSnapshot plan,
    CoachingObservation observation,
  ) async {
    final result = <int>{};
    for (final group
        in plan.exercises.map((e) => e.supersetGroup).nonNulls.toSet()) {
      var unstarted = true;
      for (final e in plan.exercises.where((e) => e.supersetGroup == group)) {
        final ref = await codec.exerciseRef(e.exerciseId);
        final p = observation.original
            .where((p) => p['exercise'] == ref)
            .firstOrNull;
        if (e.trainingMethod == 'max_effort') unstarted = false;
        if (p == null ||
            (observation.actualFor(p)?['completed'] as int? ?? 0) > 0)
          unstarted = false;
      }
      if (unstarted) result.add(group);
    }
    return result;
  }

  List<PlannedExerciseSnapshot> _fitWorkUnits(
    List<PlannedExerciseSnapshot> missing,
    PlannedSessionSnapshot base, {
    int? budget,
    int? availableMinutes,
  }) {
    final units = <List<PlannedExerciseSnapshot>>[];
    final groups = <int, List<PlannedExerciseSnapshot>>{};
    for (final e in missing) {
      if (e.supersetGroup == null) {
        units.add([e]);
      } else {
        groups.putIfAbsent(e.supersetGroup!, () => []).add(e);
      }
    }
    units.addAll(groups.values);
    final chosen = <PlannedExerciseSnapshot>[];
    var group = base.exercises
        .map((e) => e.supersetGroup ?? 0)
        .fold<int>(0, math.max);
    for (final unit in units) {
      final candidate = [...chosen, ...unit];
      if (budget != null &&
          candidate.fold<int>(
                0,
                (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
              ) >
              budget)
        continue;
      if (availableMinutes != null &&
          CoachingPreviews._minutes(
                PlannedSessionSnapshot(
                  name: base.name,
                  exercises: [...base.exercises, ...candidate],
                ),
              ) >
              availableMinutes)
        continue;
      final newGroup = unit.first.supersetGroup == null ? null : ++group;
      for (final e in unit) {
        chosen.add(
          copyPlannedExercise(
            e,
            orderIndex: base.exercises.length + chosen.length,
            supersetGroup: newGroup,
          ),
        );
      }
    }
    return chosen;
  }
}
