part of '../programs_repository.dart';

/// Slotless days (manual blocks, snapshotted templates) hold one copy of
/// every exercise per week, so a scoped replacement has to find the same
/// row in the sibling days of the other weeks: the day at the same weekday
/// (or cycle position) and order, and the row at the same order that still
/// holds the original exercise. Returns the touched day ids.
Future<List<int>> _replaceSlotlessAcrossWeeks(
  AppDatabase db, {
  required ProgramDayExerciseData original,
  required ProgramDayData originalDay,
  required ProgramWeekData originalWeek,
  required int replacementExerciseId,
  required ProgramExerciseReplacementScope scope,
}) async {
  final weeks =
      await (db.select(db.programWeeks)
            ..where((t) => t.programId.equals(originalWeek.programId))
            ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
          .get();
  final weekById = {for (final week in weeks) week.id: week};
  Object dayKey(ProgramDayData day) =>
      (day.cycleDayIndex ?? -day.dayOfWeek, day.orderIndex);
  final siblingDays = await (db.select(
    db.programDays,
  )..where((t) => t.programWeekId.isIn(weekById.keys))).get();
  final key = dayKey(originalDay);

  // weekIndex → the matching row in that week, if it still holds the
  // original exercise.
  final rowByWeek = <int, ProgramDayExerciseData>{};
  for (final day in siblingDays.where((day) => dayKey(day) == key)) {
    final rows = await (db.select(
      db.programDayExercises,
    )..where((t) => t.programDayId.equals(day.id))).get();
    final candidates = rows
        .where((row) => row.exerciseId == original.exerciseId)
        .toList();
    final match =
        candidates
            .where((row) => row.orderIndex == original.orderIndex)
            .firstOrNull ??
        (candidates.length == 1 ? candidates.single : null);
    final week = weekById[day.programWeekId];
    if (match != null && week != null) rowByWeek[week.weekIndex] = match;
  }
  rowByWeek[originalWeek.weekIndex] = original;

  final current = originalWeek.weekIndex;
  var waveStart = current;
  var waveEnd = current;
  while (rowByWeek.containsKey(waveStart - 1)) {
    waveStart--;
  }
  while (rowByWeek.containsKey(waveEnd + 1)) {
    waveEnd++;
  }
  final targets = [
    for (final MapEntry(key: weekIndex, value: row) in rowByWeek.entries)
      if (switch (scope) {
        ProgramExerciseReplacementScope.thisWave =>
          weekIndex >= waveStart && weekIndex <= waveEnd,
        ProgramExerciseReplacementScope.thisAndFutureWaves =>
          weekIndex >= current,
        ProgramExerciseReplacementScope.entireBlock => true,
      })
        row,
  ];
  await (db.update(
    db.programDayExercises,
  )..where((t) => t.id.isIn(targets.map((row) => row.id)))).write(
    ProgramDayExercisesCompanion(
      exerciseId: Value(replacementExerciseId),
      equipmentVariant: const Value(null),
    ),
  );
  return targets.map((row) => row.programDayId).toSet().toList();
}

/// An accepted weekly adaptation stores a frozen plan that the resolver
/// prefers over the program. Without this, a permanent swap would be
/// silently undone for any session that already has one.
Future<void> _patchAdaptationOverrides(
  AppDatabase db, {
  required List<int> dayIds,
  required int fromExerciseId,
  required int toExerciseId,
}) async {
  if (dayIds.isEmpty) return;
  final schedules =
      await (db.select(db.scheduledWorkouts)..where(
            (t) =>
                t.programDayId.isIn(dayIds) &
                t.status.isIn(const [
                  ScheduleStatus.planned,
                  ScheduleStatus.moved,
                ]),
          ))
          .get();
  if (schedules.isEmpty) return;
  final overrides =
      await (db.select(db.adaptationOverrides)..where(
            (t) =>
                t.scheduleId.isIn(schedules.map((s) => s.id)) &
                t.deletedAt.isNull(),
          ))
          .get();
  for (final override in overrides) {
    final json = jsonDecode(override.planJson) as Map<String, dynamic>;
    var changed = false;
    for (final exercise in (json['exercises'] as List? ?? const [])) {
      if (exercise is Map && exercise['exerciseId'] == fromExerciseId) {
        exercise['exerciseId'] = toExerciseId;
        changed = true;
      }
    }
    if (!changed) continue;
    await (db.update(db.adaptationOverrides)
          ..where((t) => t.id.equals(override.id)))
        .write(AdaptationOverridesCompanion(planJson: Value(jsonEncode(json))));
  }
}
