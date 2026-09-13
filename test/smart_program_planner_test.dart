import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/squat_specialization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = await openTestDatabase();
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
      movementsJson: File('assets/data/movements.json').readAsStringSync(),
      programmingMetadataJson: File(
        'assets/data/exercise_programming_metadata.json',
      ).readAsStringSync(),
    );
  });
  tearDown(() => db.close());

  test(
    'Upper/Lower/Full Body Smart plan fills every day and assigns roles',
    () async {
      final plan = SplitTemplates.generate(
        type: SplitType.upperLowerFullBody,
        daysPerWeek: 3,
      );
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Smart U/L/FB',
        weeks: 4,
        plan: plan,
        startDate: DateTime(2026, 9, 7),
        periodizationModel: 'concurrent',
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.powerbuilding,
        experienceLevel: ExperienceLevel.intermediate,
      );

      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.powerbuilding,
          experience: ExperienceLevel.intermediate,
          mainMethodByDayLabel: {'Upper': SlotTrainingMethod.maxEffort},
        ),
      );

      final weeks =
          await (db.select(db.programWeeks)
                ..where((t) => t.programId.equals(programId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      final firstWeekDays =
          await (db.select(db.programDays)
                ..where((t) => t.programWeekId.equals(weeks.first.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      expect(firstWeekDays.map((d) => d.stressRole), [
        'intensity',
        'intensity',
        'mixed',
      ]);

      final allDays = await (db.select(db.programDays).join([
        innerJoin(
          db.programWeeks,
          db.programWeeks.id.equalsExp(db.programDays.programWeekId),
        ),
      ])..where(db.programWeeks.programId.equals(programId))).get();
      for (final row in allDays) {
        final day = row.readTable(db.programDays);
        final exercises = await (db.select(
          db.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        expect(
          exercises,
          isNotEmpty,
          reason: '${day.name} should not be empty',
        );
      }

      final upper = firstWeekDays.first;
      final upperExercises =
          await (db.select(db.programDayExercises)
                ..where((t) => t.programDayId.equals(upper.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      final upperMain = upperExercises.first;
      expect(upperMain.trainingMethod, 'max_effort');
      final members = await (db.select(
        db.programSlotPoolMembers,
      )..where((t) => t.slotId.equals(upperMain.programExerciseSlotId!))).get();
      expect(members.length, greaterThanOrEqualTo(3));
    },
  );

  test('gym inventory remains a hard exercise-selection filter', () async {
    final gymId = await db
        .into(db.gyms)
        .insert(
          GymsCompanion.insert(
            name: 'Simple gym',
            isDefault: const Value(true),
            allEquipment: const Value(false),
          ),
        );
    for (final key in const [
      'barbell',
      'dumbbell',
      'cable',
      'machine_plate',
      'machine_selectorized',
      'bodyweight',
      'smith',
      'other',
    ]) {
      await db
          .into(db.gymEquipment)
          .insert(
            GymEquipmentCompanion.insert(gymId: gymId, equipmentKey: key),
          );
    }
    final plan = SplitTemplates.generate(
      type: SplitType.fullBodyLinear,
      daysPerWeek: 3,
    );
    final programId = await ProgramsRepository(db).createProgramFromSplit(
      name: 'Equipment filter',
      weeks: 2,
      plan: plan,
      startDate: DateTime(2026, 9, 7),
    );
    await SmartProgramPlanner(db).populate(
      programId,
      SmartProgramConfiguration(
        goal: TrainingGoal.hypertrophy,
        experience: ExperienceLevel.intermediate,
        gymId: gymId,
      ),
    );

    final selectedIds = (await db.select(db.rotationAssignments).get())
        .map((row) => row.exerciseId)
        .toSet();
    final selected = await (db.select(
      db.exerciseCatalog,
    )..where((t) => t.id.isIn(selectedIds))).get();
    expect(
      selected.any(
        (exercise) =>
            exercise.requiredEquipmentKeys?.contains('cambered_bar') ?? false,
      ),
      isFalse,
    );
  });

  test('four-day Conjugate maps to two ME and two dynamic days', () async {
    final programId = await ProgramsRepository(db).createProgramFromSplit(
      name: 'Conjugate four day',
      weeks: 4,
      plan: SplitTemplates.generate(type: SplitType.upperLower, daysPerWeek: 4),
      startDate: DateTime(2026, 9, 7),
      periodizationModel: 'max_effort',
      buildMode: ProgramBuildMode.smart,
      trainingGoal: TrainingGoal.strength,
      experienceLevel: ExperienceLevel.advanced,
    );
    await SmartProgramPlanner(db).populate(
      programId,
      const SmartProgramConfiguration(
        goal: TrainingGoal.strength,
        experience: ExperienceLevel.advanced,
      ),
    );

    final week =
        await (db.select(db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)])
              ..limit(1))
            .getSingle();
    final days =
        await (db.select(db.programDays)
              ..where((t) => t.programWeekId.equals(week.id))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    expect(days.map((day) => day.stressRole), [
      'intensity',
      'intensity',
      'dynamic_technique',
      'dynamic_technique',
    ]);

    final methods = <String>[];
    for (final day in days) {
      final main =
          await (db.select(db.programDayExercises)
                ..where((t) => t.programDayId.equals(day.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
                ..limit(1))
              .getSingleOrNull();
      methods.add(main!.trainingMethod);
    }
    expect(methods, [
      'max_effort',
      'max_effort',
      'dynamic_effort',
      'dynamic_effort',
    ]);

    final firstMain =
        await (db.select(db.programDayExercises)
              ..where((t) => t.programDayId.equals(days.first.id))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
              ..limit(1))
            .getSingle();
    final rotation =
        await (db.select(db.rotationAssignments)
              ..where((t) => t.slotId.equals(firstMain.programExerciseSlotId!))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
            .get();
    expect(rotation[0].exerciseId, isNot(rotation[1].exerciseId));
  });

  test(
    'novice linear full-body plan never creates Dynamic Effort slots',
    () async {
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Novice linear full body',
        weeks: 4,
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyLinear,
          daysPerWeek: 3,
        ),
        startDate: DateTime(2026, 9, 7),
        periodizationModel: 'linear',
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.strength,
        experienceLevel: ExperienceLevel.novice,
      );

      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.strength,
          experience: ExperienceLevel.novice,
        ),
      );

      final days = await (db.select(db.programDays).join([
        innerJoin(
          db.programWeeks,
          db.programWeeks.id.equalsExp(db.programDays.programWeekId),
        ),
      ])..where(db.programWeeks.programId.equals(programId))).get();
      expect(
        days.map((row) => row.readTable(db.programDays).stressRole),
        isNot(contains('dynamic_technique')),
      );

      final exercises = await (db.select(db.programDayExercises).join([
        innerJoin(
          db.programDays,
          db.programDays.id.equalsExp(db.programDayExercises.programDayId),
        ),
        innerJoin(
          db.programWeeks,
          db.programWeeks.id.equalsExp(db.programDays.programWeekId),
        ),
      ])..where(db.programWeeks.programId.equals(programId))).get();
      expect(
        exercises.map(
          (row) => row.readTable(db.programDayExercises).trainingMethod,
        ),
        isNot(contains('dynamic_effort')),
      );
    },
  );

  test(
    'manual concurrent A/B honours day roles, rotation cadence and alternating muscle focus',
    () async {
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Manual concurrent focus',
        weeks: 4,
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyAb,
          daysPerWeek: 2,
        ),
        startDate: DateTime(2026, 9, 7),
        periodizationModel: 'concurrent',
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.powerbuilding,
        experienceLevel: ExperienceLevel.intermediate,
      );
      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.powerbuilding,
          experience: ExperienceLevel.intermediate,
          dayRoles: {
            'Full Body A': DayStressRole.volume,
            'Full Body B': DayStressRole.intensity,
          },
          musclePriorities: {'chest': 'high', 'quads': 'medium'},
          muscleVolumeWeights: {'chest': .6, 'quads': .4},
          weeklySetCaps: {'chest': 10, 'quads': 15},
          muscleFocusWave: MuscleFocusWave.alternating,
          waveOverrideWeeks: 2,
        ),
      );

      final weeks =
          await (db.select(db.programWeeks)
                ..where((t) => t.programId.equals(programId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      final firstDays =
          await (db.select(db.programDays)
                ..where((t) => t.programWeekId.equals(weeks.first.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      expect(firstDays.map((day) => day.stressRole), ['volume', 'intensity']);

      final slots = await (db.select(
        db.programExerciseSlots,
      )..where((t) => t.programId.equals(programId))).get();
      expect(slots, isNotEmpty);
      expect(slots.every((slot) => slot.waveOverrideWeeks == 2), isTrue);

      final changingSlot = slots.first;
      final rotations =
          await (db.select(db.rotationAssignments)
                ..where((t) => t.slotId.equals(changingSlot.id))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      expect(rotations[0].exerciseId, rotations[1].exerciseId);
      expect(rotations[1].exerciseId, isNot(rotations[2].exerciseId));

      final exerciseRows = await db.select(db.programDayExercises).get();
      expect(
        exerciseRows.any(
          (row) => row.prescriptionWhy?.contains('high-focus week') ?? false,
        ),
        isTrue,
      );
      expect(
        exerciseRows.any(
          (row) => row.prescriptionWhy?.contains('lighter-focus week') ?? false,
        ),
        isTrue,
      );
    },
  );

  test(
    'short sessions use opted-in Myo-reps only for isolation slots',
    () async {
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Short hypertrophy session',
        weeks: 2,
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyAb,
          daysPerWeek: 2,
        ),
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.hypertrophy,
        experienceLevel: ExperienceLevel.intermediate,
      );
      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 45,
          allowTimeSavingSetTechniques: true,
        ),
      );

      final rows = await db.select(db.programDayExercises).get();
      final compressed = rows
          .where((row) => row.setType == 'myo_reps')
          .toList();
      expect(compressed, isNotEmpty);
      expect(
        compressed.every((row) => row.slotRole == SlotRole.isolation.id),
        isTrue,
      );
      expect(compressed.every((row) => row.targetRir == 0), isTrue);
      expect(compressed.every((row) => row.prescriptionJson != null), isTrue);
    },
  );

  test('squat specialization centres full-body days on a safe squat', () async {
    final programId = await ProgramsRepository(db).createProgramFromSplit(
      name: '140 kg squat block',
      weeks: 16,
      plan: SplitTemplates.generate(type: SplitType.fullBody, daysPerWeek: 3),
      startDate: DateTime(2026, 9, 7),
      buildMode: ProgramBuildMode.smart,
      trainingGoal: TrainingGoal.strength,
      experienceLevel: ExperienceLevel.intermediate,
    );
    await SmartProgramPlanner(db).populate(
      programId,
      const SmartProgramConfiguration(
        goal: TrainingGoal.strength,
        experience: ExperienceLevel.intermediate,
        squatSpecialization: SquatSpecialization(
          currentKg: 110,
          targetKg: 140,
          weeks: 16,
          stickingPoint: SquatStickingPoint.bottom,
        ),
      ),
    );

    final days = await db.select(db.programDays).get();
    for (final day in days) {
      final main =
          await (db.select(db.programDayExercises)
                ..where((row) => row.programDayId.equals(day.id))
                ..orderBy([(row) => OrderingTerm(expression: row.orderIndex)])
                ..limit(1))
              .getSingle();
      final exercise = await (db.select(
        db.exerciseCatalog,
      )..where((row) => row.id.equals(main.exerciseId))).getSingle();
      expect(main.slotRole, SlotRole.main.id);
      expect(exercise.movementPattern, 'squat');
    }
  });

  test(
    'bench specialization centres full-body days on horizontal pressing',
    () async {
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Bench block',
        weeks: 12,
        plan: SplitTemplates.generate(type: SplitType.fullBody, daysPerWeek: 3),
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.strength,
        experienceLevel: ExperienceLevel.intermediate,
      );
      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.strength,
          experience: ExperienceLevel.intermediate,
          primaryLiftSpecialization: PrimaryLiftSpecialization(
            lift: PrimaryLift.benchPress,
            currentKg: 90,
            targetKg: 110,
            weeks: 12,
            stickingPoint: PrimaryLiftStickingPoint.chest,
          ),
        ),
      );

      final days = await db.select(db.programDays).get();
      for (final day in days) {
        final main =
            await (db.select(db.programDayExercises)
                  ..where((row) => row.programDayId.equals(day.id))
                  ..orderBy([(row) => OrderingTerm(expression: row.orderIndex)])
                  ..limit(1))
                .getSingle();
        final exercise = await (db.select(
          db.exerciseCatalog,
        )..where((row) => row.id.equals(main.exerciseId))).getSingle();
        expect(exercise.movementPattern, 'horizontal_push');
      }
    },
  );
}
