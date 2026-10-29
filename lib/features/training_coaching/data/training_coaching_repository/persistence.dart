part of '../training_coaching_repository.dart';

extension _CoachingPersistence on TrainingCoachingRepository {
  Future<void> _persistDay(int dayId, PlannedSessionSnapshot plan) async {
    final day = await (db.select(
      db.programDays,
    )..where((d) => d.id.equals(dayId))).getSingle();
    final week = await (db.select(
      db.programWeeks,
    )..where((w) => w.id.equals(day.programWeekId))).getSingle();
    if (day.templateId != null) {
      // Own a copy of just this day's template. Keep literal targets and
      // warmups; editing the shared library template would affect other days.
      final copied = <PlannedExerciseSnapshot>[];
      for (final e in plan.exercises) {
        final sets = e.sets.toList();
        final working = sets.where((s) => !s.isWarmup).toList();
        if (week.adjustmentFactor < 1 && working.isNotEmpty) {
          if (week.adjustmentFactor <= 0)
            throw StateError('This week has no training volume.');
          final unscaled =
              ((working.length - 1) / week.adjustmentFactor).floor() + 1;
          while (sets.where((s) => !s.isWarmup).length < unscaled) {
            sets.add(working.last.copyWith(index: sets.length + 1));
          }
        }
        copied.add(copyPlannedExercise(e, sets: sets));
      }
      final template = await TemplatesRepository(db).createFromPlannedSession(
        PlannedSessionSnapshot(name: plan.name, exercises: copied),
        name: '${plan.name} · coaching',
      );
      await (db.update(db.programDays)..where((d) => d.id.equals(dayId))).write(
        ProgramDaysCompanion(templateId: Value(template.id)),
      );
      return;
    }
    final before = await PlannedSessionResolver(
      db,
      clock: clock,
    ).resolveProgramDay(dayId);
    final oldRows = await (db.select(
      db.programDayExercises,
    )..where((e) => e.programDayId.equals(dayId))).get();
    final used = <int>{};
    for (final e in plan.exercises) {
      final old = oldRows
          .where(
            (r) =>
                !used.contains(r.id) &&
                (e.programExerciseSlotId != null
                    ? r.programExerciseSlotId == e.programExerciseSlotId
                    : r.exerciseId == e.exerciseId),
          )
          .firstOrNull;
      if (old != null) used.add(old.id);
      final previous = before.exercises
          .where(
            (p) => e.programExerciseSlotId != null
                ? p.programExerciseSlotId == e.programExerciseSlotId
                : p.exerciseId == e.exerciseId,
          )
          .firstOrNull;
      final unchanged =
          previous != null &&
          await codec.encode(
                PlannedSessionSnapshot(
                  name: '',
                  exercises: [copyPlannedExercise(previous, orderIndex: 0)],
                ),
              ) ==
              await codec.encode(
                PlannedSessionSnapshot(
                  name: '',
                  exercises: [copyPlannedExercise(e, orderIndex: 0)],
                ),
              );
      if (old != null && unchanged) {
        await (db.update(
          db.programDayExercises,
        )..where((r) => r.id.equals(old.id))).write(
          ProgramDayExercisesCompanion(orderIndex: Value(e.orderIndex)),
        );
        continue;
      }
      final working = e.sets.where((s) => !s.isWarmup).toList();
      final prescription = SlotPrescription(
        name: 'User-confirmed coaching change',
        segments: [
          for (final s in working)
            WorkSegment(
              sets: 1,
              repsMin: s.repsMin ?? 0,
              repsMax: s.repsMax,
              intent: Intent.fromId(s.intent),
              percentOf1Rm: s.percentOf1Rm,
              setType: SetType.fromId(s.setType),
              restSeconds: e.restSeconds,
              meta: {
                if (s.setTypeMetaJson != null)
                  ...Map<String, Object?>.from(
                    jsonDecode(s.setTypeMetaJson!) as Map,
                  ),
                if (s.weightKg != null) 'coachingWeightKg': s.weightKg,
              },
            ),
        ],
      );
      final changes = ProgramDayExercisesCompanion(
        exerciseId: Value(e.exerciseId),
        orderIndex: Value(e.orderIndex),
        targetSets: Value(working.length),
        targetRepsMin: Value(working.firstOrNull?.repsMin),
        targetRepsMax: Value(working.firstOrNull?.repsMax),
        targetRir: Value(working.firstOrNull?.rir),
        targetRpe: Value(
          working.firstOrNull?.rpeX10 == null
              ? null
              : (working.first.rpeX10! / 10).round(),
        ),
        slotRole: Value(e.slotRole),
        trainingMethod: Value(e.trainingMethod),
        programExerciseSlotId: Value(e.programExerciseSlotId),
        restSeconds: Value(e.restSeconds),
        equipmentVariant: Value(e.equipmentVariant),
        supersetGroup: Value(e.supersetGroup),
        sessionSegment: Value(e.sessionSegment),
        prescriptionWhy: Value(e.why),
        prescriptionCodecJson: Value(
          SlotPrescriptionCodec.encode(prescription),
        ),
      );
      if (old != null) {
        await (db.update(
          db.programDayExercises,
        )..where((r) => r.id.equals(old.id))).write(changes);
      } else {
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: e.exerciseId,
                orderIndex: e.orderIndex,
              ).copyWith(
                targetSets: changes.targetSets,
                targetRepsMin: changes.targetRepsMin,
                targetRepsMax: changes.targetRepsMax,
                targetRir: changes.targetRir,
                targetRpe: changes.targetRpe,
                slotRole: changes.slotRole,
                trainingMethod: changes.trainingMethod,
                programExerciseSlotId: changes.programExerciseSlotId,
                restSeconds: changes.restSeconds,
                equipmentVariant: changes.equipmentVariant,
                supersetGroup: changes.supersetGroup,
                sessionSegment: changes.sessionSegment,
                prescriptionWhy: changes.prescriptionWhy,
                prescriptionCodecJson: changes.prescriptionCodecJson,
              ),
            );
      }
    }
    await (db.delete(db.programDayExercises)..where(
          (r) =>
              r.programDayId.equals(dayId) &
              r.id.isIn(
                oldRows.where((r) => !used.contains(r.id)).map((r) => r.id),
              ),
        ))
        .go();
  }
}
