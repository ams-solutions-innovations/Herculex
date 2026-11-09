part of '../programs_repository.dart';

/// Reads and writes behind "update this block": adherence for the advisor,
/// carrying the user's own exercise choices into a regenerated block, and
/// retiring the old block without touching anything already trained.
extension ProgramsBlockUpdate on ProgramsRepository {
  /// Planned vs. done sessions for each of the [weeks] full Monday–Sunday
  /// weeks before the one containing [now], oldest first.
  Future<List<WeekAdherence>> recentAdherence(
    int programId, {
    required DateTime now,
    int weeks = 3,
  }) async {
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final from = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - 7 * weeks,
    );
    final rows =
        await (_db.select(_db.scheduledWorkouts)..where(
              (t) =>
                  t.programId.equals(programId) &
                  t.deletedAt.isNull() &
                  t.dateIso.isBiggerOrEqualValue(_isoDate(from)) &
                  t.dateIso.isSmallerThanValue(_isoDate(thisMonday)),
            ))
            .get();
    return [
      for (var i = 0; i < weeks; i++)
        () {
          final start = DateTime(from.year, from.month, from.day + 7 * i);
          final end = DateTime(start.year, start.month, start.day + 7);
          final inWeek = rows.where((row) {
            final date = DateTime.parse(row.dateIso);
            return !date.isBefore(start) && date.isBefore(end);
          });
          return (
            planned: inWeek.length,
            done: inWeek
                .where((row) => row.status == ScheduleStatus.done)
                .length,
          );
        }(),
    ];
  }

  /// Template linked to each slot label in the block's first week. A manual
  /// block is rebuilt from the same templates rather than by the planner.
  Future<Map<String, int>> templatesBySlotLabel(int programId) async {
    final firstWeek =
        await (_db.select(_db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)])
              ..limit(1))
            .getSingleOrNull();
    if (firstWeek == null) return const {};
    final days = await (_db.select(
      _db.programDays,
    )..where((t) => t.programWeekId.equals(firstWeek.id))).get();
    return {
      for (final day in days)
        if (day.templateId != null)
          (day.slotLabel ?? day.name): day.templateId!,
    };
  }

  /// Copies exercises the user picked by hand in [fromProgramId] onto the
  /// matching slots (same slot key) of [toProgramId], for every week.
  Future<void> carryUserExerciseChoices({
    required int fromProgramId,
    required int toProgramId,
  }) async {
    final oldSlots = await (_db.select(
      _db.programExerciseSlots,
    )..where((t) => t.programId.equals(fromProgramId))).get();
    if (oldSlots.isEmpty) return;
    final newSlots = await (_db.select(
      _db.programExerciseSlots,
    )..where((t) => t.programId.equals(toProgramId))).get();
    final newSlotByKey = {for (final slot in newSlots) slot.slotKey: slot};
    // A block built before A/B day names has `upper-intensity-main-0` where
    // its rebuild has `upper-a-intensity-main-0`. The movement must match too,
    // because the B template puts a different lift in the same position.
    String unsuffixed(String key) => key.replaceFirst(RegExp(r'-[ab]-'), '-');
    final newSlotsByUnsuffixedKey = {
      for (final slot in newSlots) unsuffixed(slot.slotKey): slot,
    };

    await _db.transaction(() async {
      for (final slot in oldSlots) {
        final renamed = newSlotsByUnsuffixedKey[slot.slotKey];
        final target =
            newSlotByKey[slot.slotKey] ??
            (renamed?.movementPattern == slot.movementPattern &&
                    renamed?.primaryMuscle == slot.primaryMuscle
                ? renamed
                : null);
        if (target == null) continue;
        final choice =
            await (_db.select(_db.rotationAssignments)
                  ..where(
                    (t) => t.slotId.equals(slot.id) & t.source.equals('user'),
                  )
                  ..orderBy([
                    (t) => OrderingTerm(
                      expression: t.weekIndex,
                      mode: OrderingMode.desc,
                    ),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (choice == null) continue;
        await (_db.update(
          _db.rotationAssignments,
        )..where((t) => t.slotId.equals(target.id))).write(
          RotationAssignmentsCompanion(
            exerciseId: Value(choice.exerciseId),
            source: const Value('user'),
            reason: const Value('Kept from your previous block.'),
          ),
        );
        await (_db.update(
          _db.programDayExercises,
        )..where((t) => t.programExerciseSlotId.equals(target.id))).write(
          ProgramDayExercisesCompanion(
            exerciseId: Value(choice.exerciseId),
            equipmentVariant: const Value(null),
          ),
        );
        await (_db.update(
          _db.programExerciseSlots,
        )..where((t) => t.id.equals(target.id))).write(
          const ProgramExerciseSlotsCompanion(userLocked: Value(true)),
        );
      }
    });
  }

  /// The generation choices a rebuilt block must keep. They live on the slots:
  /// the rotation cadence directly, the focus through its training method.
  Future<({int? rotationWeeks, TrainingFocus focus})> generationChoices(
    int programId,
  ) async {
    final slots = await (_db.select(
      _db.programExerciseSlots,
    )..where((t) => t.programId.equals(programId))).get();
    return (
      rotationWeeks: slots.firstOrNull?.waveOverrideWeeks,
      focus:
          slots.any(
            (slot) =>
                slot.trainingMethod == SlotTrainingMethod.intensityFocus.id,
          )
          ? TrainingFocus.intensity
          : TrainingFocus.balanced,
    );
  }

  /// Ends [programId] at [from]: its untouched future sessions go, every
  /// session the user started, trained, moved or skipped stays as history,
  /// and the block is archived.
  Future<void> retireForReplacement(int programId, DateTime from) async {
    await _db.transaction(() async {
      await (_db.delete(_db.scheduledWorkouts)..where(
            (t) =>
                t.programId.equals(programId) &
                t.status.equals(ScheduleStatus.planned) &
                t.completedSessionId.isNull() &
                t.dateIso.isBiggerOrEqualValue(_isoDate(from)),
          ))
          .go();
      await archiveProgram(programId);
    });
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
