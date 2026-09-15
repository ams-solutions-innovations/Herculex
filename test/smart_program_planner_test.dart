import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/squat_specialization.dart';

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

  test(
    'a SlotRole.main slot stays locked to the same exercise across every '
    'week of a generated block (D-09/D-10)',
    () async {
      final plan = SplitTemplates.generate(
        type: SplitType.upperLowerFullBody,
        daysPerWeek: 3,
      );
      final programId = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Anchor lock U/L/FB',
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
        ),
      );

      final firstWeek =
          await (db.select(db.programWeeks)
                ..where((t) => t.programId.equals(programId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)])
                ..limit(1))
              .getSingle();
      final firstWeekDays =
          await (db.select(db.programDays)
                ..where((t) => t.programWeekId.equals(firstWeek.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();

      var checkedAtLeastOneMainSlot = false;
      for (final day in firstWeekDays) {
        final dayExercises =
            await (db.select(db.programDayExercises)
                  ..where((t) => t.programDayId.equals(day.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();
        for (final exercise in dayExercises) {
          final slotId = exercise.programExerciseSlotId;
          if (slotId == null || exercise.slotRole != SlotRole.main.id) {
            continue;
          }
          final assignments =
              await (db.select(db.rotationAssignments)
                    ..where((t) => t.slotId.equals(slotId))
                    ..orderBy([
                      (t) => OrderingTerm(expression: t.weekIndex),
                    ]))
                  .get();
          expect(
            assignments.map((a) => a.exerciseId).toSet().length,
            1,
            reason:
                'SlotRole.main slot $slotId must resolve to the identical '
                'exerciseId across all weeks',
          );
          checkedAtLeastOneMainSlot = true;
        }
      }
      expect(
        checkedAtLeastOneMainSlot,
        isTrue,
        reason: 'the generated program must contain at least one main slot',
      );
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
    // D-09/D-10 (Phase 17): SlotRole.main is anchor-locked to a specific
    // exercise across every week of the block, superseding the previous
    // week-to-week Max Effort rotation cadence — the slot's pool of 3+
    // variations remains available for the (future, Phase 19) manual
    // replacement flow, but automatic rotation no longer swaps the anchor.
    expect(rotation[0].exerciseId, rotation[1].exerciseId);
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

  group('verifyPrerequisites wiring (Task 2)', () {
    // `AppDatabase.forTesting`'s `onCreate` still seeds the full real
    // exercise catalog (`ExerciseImporter.runFromAsset`), so a "fresh"
    // fixture db is not catalog-empty. A default gym with zero equipment
    // rows hard-excludes every real catalog exercise via the ordinary
    // equipment gate (every real row needs at least one key, even the
    // bodyweight modality fallback) while our synthetic fixture rows use
    // `requiredEquipmentKeys: '[]'`, which trivially satisfies
    // `_EquipmentProfile.allows` regardless of what's available. This keeps
    // the fixture "synthetic, catalog-independent" (Pitfall 4) without
    // needing an empty catalog.
    late AppDatabase fixtureDb;
    setUp(() async {
      fixtureDb = await openTestDatabase();
      await fixtureDb
          .into(fixtureDb.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
    });
    tearDown(() => fixtureDb.close());

    Future<int> insertExercise({
      required String slug,
      required String name,
      required String primaryMuscle,
      String difficulty = 'novice',
      String? prerequisiteSlugs,
    }) => fixtureDb
        .into(fixtureDb.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            slug: Value(slug),
            name: name,
            primaryMuscle: primaryMuscle,
            equipment: 'bodyweight',
            mechanics: 'compound',
            force: 'push',
            plane: 'none',
            category: const Value('cardio'),
            modality: const Value('bodyweight'),
            loggingMetric: const Value('time'),
            programmingDifficulty: Value(difficulty),
            programmingCommonness: const Value('basic'),
            allowedTrainingStyles: const Value('["weightlifting"]'),
            technicalEligibility: const Value('automatic'),
            requiredEquipmentKeys: const Value('[]'),
            prerequisiteSlugs: Value(prerequisiteSlugs),
          ),
        );

    Future<int> createGppProgram() {
      final plan = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 1,
        customSlots: const ['GPP'],
      );
      return ProgramsRepository(fixtureDb).createProgramFromSplit(
        name: 'Prerequisite fixture',
        weeks: 1,
        plan: plan,
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.athletic,
        experienceLevel: ExperienceLevel.novice,
      );
    }

    test(
      'a prerequisite-gated exercise is excluded until history satisfies it, then included',
      () async {
        // Always eligible (no prerequisiteSlugs) — proves bullet 3 of the
        // plan's <behavior>: an exercise with no prerequisites is never
        // excluded by this gate, and keeps the pool non-empty pre-Task-3.
        final fillerId = await insertExercise(
          slug: 'filler-exercise',
          name: 'Filler Exercise',
          primaryMuscle: 'Control',
        );
        // Deliberately harder than the novice test user so Condition (a)
        // (experience >= prerequisite difficulty) fails, forcing reliance
        // on Condition (b) (logged completion history).
        final prereqId = await insertExercise(
          slug: 'prerequisite-exercise',
          name: 'Prerequisite Exercise',
          primaryMuscle: 'Control',
          difficulty: 'advanced',
        );
        final dependentId = await insertExercise(
          slug: 'dependent-exercise',
          name: 'Dependent Exercise',
          primaryMuscle: 'Control',
          prerequisiteSlugs: '["prerequisite-exercise"]',
        );

        // Excluded: novice user, no history satisfying the prerequisite.
        final excludedProgramId = await createGppProgram();
        await SmartProgramPlanner(fixtureDb).populate(
          excludedProgramId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.athletic,
            experience: ExperienceLevel.novice,
          ),
        );
        final excludedDay = await (fixtureDb.select(
          fixtureDb.programDays,
        )..limit(1)).getSingle();
        final excludedSlot = await (fixtureDb.select(
          fixtureDb.programExerciseSlots,
        )..where((t) => t.daySlotLabel.equals('GPP'))).getSingle();
        final excludedMembers = await (fixtureDb.select(
          fixtureDb.programSlotPoolMembers,
        )..where((t) => t.slotId.equals(excludedSlot.id))).get();
        expect(
          excludedMembers.map((m) => m.exerciseId),
          [fillerId],
          reason:
              'the dependent exercise must never enter the candidate pool '
              'before its prerequisite has been satisfied, and the '
              'advanced-difficulty prerequisite itself is separately '
              'excluded from a novice plan',
        );
        final excludedExercises = await (fixtureDb.select(
          fixtureDb.programDayExercises,
        )..where((t) => t.programDayId.equals(excludedDay.id))).get();
        expect(excludedExercises.single.exerciseId, fillerId);

        // Included: a completed session referencing the prerequisite unlocks it.
        final session = await fixtureDb
            .into(fixtureDb.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                startedAt: DateTime(2026, 8, 1),
                endedAt: Value(DateTime(2026, 8, 1, 1)),
              ),
            );
        await fixtureDb
            .into(fixtureDb.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                sessionId: session,
                exerciseId: prereqId,
                orderIndex: 0,
              ),
            );

        final includedProgramId = await createGppProgram();
        await SmartProgramPlanner(fixtureDb).populate(
          includedProgramId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.athletic,
            experience: ExperienceLevel.novice,
          ),
        );
        final includedSlot = await (fixtureDb.select(
          fixtureDb.programExerciseSlots,
        )..where(
          (t) =>
              t.programId.equals(includedProgramId) &
              t.daySlotLabel.equals('GPP'),
        )).getSingle();
        final includedMembers = await (fixtureDb.select(
          fixtureDb.programSlotPoolMembers,
        )..where((t) => t.slotId.equals(includedSlot.id))).get();
        expect(
          includedMembers.map((m) => m.exerciseId).toSet(),
          {fillerId, dependentId},
          reason:
              'once the prerequisite is completed, the dependent exercise '
              'becomes a valid candidate alongside the never-gated filler '
              '(the advanced-difficulty prerequisite itself stays excluded '
              'from this novice plan on its own difficulty ceiling)',
        );
      },
    );
  });

  group('empty-slot resolution on hard-filter exhaustion (Task 3, D-01/D-03)', () {
    // Same real-catalog-seeding caveat and zero-equipment-gym isolation
    // trick as the Task 2 group above. `horizontal_pull` is used as the
    // target need's pattern because no real catalog exercise carries that
    // movementPattern with a scaling ladder attached (verified against
    // assets/data/exercise_programming_metadata.json), so it exercises the
    // "no ladder for this pattern" path cleanly without incidental
    // real-catalog interference either way.
    late AppDatabase fixtureDb;
    setUp(() async {
      fixtureDb = await openTestDatabase();
      await fixtureDb
          .into(fixtureDb.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
    });
    tearDown(() => fixtureDb.close());

    Future<int> insertExercise({
      required String slug,
      required String name,
      required String primaryMuscle,
      String? movementPattern,
      String mechanics = 'compound',
      String modality = 'barbell',
      int cnsScore = 3,
      String difficulty = 'novice',
      String? scalingGroup,
      int? scalingOrder,
    }) => fixtureDb
        .into(fixtureDb.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            slug: Value(slug),
            name: name,
            primaryMuscle: primaryMuscle,
            equipment: modality,
            mechanics: mechanics,
            force: 'push',
            plane: 'none',
            movementPattern: Value(movementPattern),
            modality: Value(modality),
            cnsScore: Value(cnsScore),
            programmingDifficulty: Value(difficulty),
            programmingCommonness: const Value('basic'),
            allowedTrainingStyles: const Value('["weightlifting"]'),
            technicalEligibility: const Value('automatic'),
            requiredEquipmentKeys: const Value('[]'),
            scalingGroup: Value(scalingGroup),
            scalingOrder: Value(scalingOrder),
          ),
        );

    Future<int> createPullDayProgram() {
      final plan = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 1,
        customSlots: const ['Pull Day'],
      );
      return ProgramsRepository(fixtureDb).createProgramFromSplit(
        name: 'Empty-slot fixture',
        weeks: 1,
        plan: plan,
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.hypertrophy,
        experienceLevel: ExperienceLevel.novice,
      );
    }

    test(
      'a hard-filter-exhausted slot with no scaling ladder resolves to '
      'empty; every other slot on the day still resolves',
      () async {
        // Deliberately no exercise matches `horizontal_pull` + `main` role
        // eligibility (cnsScore >= 5 with a max-effort-capable modality),
        // and none of these carry a scaling ladder, so the target slot must
        // resolve to SelectionExplanation.empty(...) via the "no ladder"
        // path.
        final verticalPullId = await insertExercise(
          slug: 'vertical-pull-filler',
          name: 'Vertical Pull Filler',
          primaryMuscle: 'Lats',
          movementPattern: 'vertical_pull',
        );
        final horizontalPullAccessoryId = await insertExercise(
          slug: 'horizontal-pull-accessory-filler',
          name: 'Horizontal Pull Accessory Filler',
          primaryMuscle: 'Back',
          movementPattern: 'horizontal_pull',
        );
        final bicepId = await insertExercise(
          slug: 'bicep-filler',
          name: 'Bicep Filler',
          primaryMuscle: 'Biceps',
          mechanics: 'isolation',
        );
        final rearId = await insertExercise(
          slug: 'rear-filler',
          name: 'Rear Delt Filler',
          primaryMuscle: 'Rear Delts',
          mechanics: 'isolation',
        );

        final programId = await createPullDayProgram();
        await SmartProgramPlanner(fixtureDb).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.novice,
          ),
        );

        final day = await (fixtureDb.select(
          fixtureDb.programDays,
        )..limit(1)).getSingle();
        final exercises = await (fixtureDb.select(
          fixtureDb.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        final byOrder = {for (final e in exercises) e.orderIndex: e};

        expect(
          byOrder.containsKey(0),
          isFalse,
          reason:
              'the main horizontal_pull slot (index 0) has no eligible '
              'candidate and no scaling ladder, so it must be skipped '
              'entirely rather than throwing',
        );
        expect(byOrder[1]!.exerciseId, verticalPullId);
        expect(byOrder[2]!.exerciseId, horizontalPullAccessoryId);
        expect(byOrder[3]!.exerciseId, bicepId);
        expect(byOrder[4]!.exerciseId, rearId);
      },
    );

    test(
      'a hard-filter-exhausted slot with a safe scaling regression is '
      'filled by the regressed candidate instead of left empty',
      () async {
        // Excluded from the ordinary candidate search by its own difficulty
        // ceiling (advanced > novice) — this is what forces the empty-pool
        // resolver to run at all.
        await insertExercise(
          slug: 'pull-ladder-target',
          name: 'Pull Ladder Target',
          primaryMuscle: 'Lats',
          movementPattern: 'horizontal_pull',
          cnsScore: 5,
          difficulty: 'advanced',
          scalingGroup: 'pull_ladder',
          scalingOrder: 3,
        );
        // Excluded from the ordinary candidate search by role (cnsScore < 5
        // means it never earns the `main` eligibility flag), but a fully
        // eligible, safe regression via ExerciseScalingResolver.
        final regressionId = await insertExercise(
          slug: 'pull-ladder-regression',
          name: 'Pull Ladder Regression',
          primaryMuscle: 'Lats',
          movementPattern: 'horizontal_pull',
          cnsScore: 3,
          difficulty: 'novice',
          scalingGroup: 'pull_ladder',
          scalingOrder: 1,
        );
        final verticalPullId = await insertExercise(
          slug: 'vertical-pull-filler-2',
          name: 'Vertical Pull Filler',
          primaryMuscle: 'Lats',
          movementPattern: 'vertical_pull',
        );
        final horizontalPullAccessoryId = await insertExercise(
          slug: 'horizontal-pull-accessory-filler-2',
          name: 'Horizontal Pull Accessory Filler',
          primaryMuscle: 'Back',
          movementPattern: 'horizontal_pull',
        );
        final bicepId = await insertExercise(
          slug: 'bicep-filler-2',
          name: 'Bicep Filler',
          primaryMuscle: 'Biceps',
          mechanics: 'isolation',
        );
        final rearId = await insertExercise(
          slug: 'rear-filler-2',
          name: 'Rear Delt Filler',
          primaryMuscle: 'Rear Delts',
          mechanics: 'isolation',
        );
        final programId = await createPullDayProgram();
        await SmartProgramPlanner(fixtureDb).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.novice,
          ),
        );

        final day = await (fixtureDb.select(
          fixtureDb.programDays,
        )..limit(1)).getSingle();
        final exercises = await (fixtureDb.select(
          fixtureDb.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        final byOrder = {for (final e in exercises) e.orderIndex: e};

        expect(
          byOrder[0]!.exerciseId,
          regressionId,
          reason:
              'the safe regression candidate must fill the slot instead of '
              'it being left empty',
        );
        expect(byOrder[1]!.exerciseId, verticalPullId);
        expect(byOrder[2]!.exerciseId, horizontalPullAccessoryId);
        expect(byOrder[3]!.exerciseId, bicepId);
        expect(byOrder[4]!.exerciseId, rearId);
      },
    );
  });

  group('ProgramSlotExplanations persistence for filled and empty slots '
      '(17-04 Task 1, PLAN-04)', () {
    // Same real-catalog-seeding caveat and zero-equipment-gym isolation
    // trick as the empty-slot-resolution group above. `horizontal_pull` is
    // used as the empty slot's target pattern because no real catalog
    // exercise carries that movementPattern with a scaling ladder attached,
    // so the main slot cleanly resolves to SelectionExplanation.empty(...).
    late AppDatabase fixtureDb;
    setUp(() async {
      fixtureDb = await openTestDatabase();
      await fixtureDb
          .into(fixtureDb.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
    });
    tearDown(() => fixtureDb.close());

    Future<int> insertExercise({
      required String slug,
      required String name,
      required String primaryMuscle,
      String? movementPattern,
      String mechanics = 'compound',
      String modality = 'barbell',
      int cnsScore = 3,
      String difficulty = 'novice',
    }) => fixtureDb
        .into(fixtureDb.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            slug: Value(slug),
            name: name,
            primaryMuscle: primaryMuscle,
            equipment: modality,
            mechanics: mechanics,
            force: 'push',
            plane: 'none',
            movementPattern: Value(movementPattern),
            modality: Value(modality),
            cnsScore: Value(cnsScore),
            programmingDifficulty: Value(difficulty),
            programmingCommonness: const Value('basic'),
            allowedTrainingStyles: const Value('["weightlifting"]'),
            technicalEligibility: const Value('automatic'),
            requiredEquipmentKeys: const Value('[]'),
          ),
        );

    test(
      'every ProgramExerciseSlots row (filled or empty) gets exactly one '
      'ProgramSlotExplanations row per week, correctly reflecting status',
      () async {
        // The main horizontal_pull slot has no eligible (cnsScore >= 5)
        // candidate and no scaling ladder for this pattern, so it resolves
        // to SelectionExplanation.empty(...).
        final horizontalPullAccessoryId = await insertExercise(
          slug: 'hp-accessory-explanations',
          name: 'Horizontal Pull Accessory Filler',
          primaryMuscle: 'Back',
          movementPattern: 'horizontal_pull',
        );
        // The supplemental vertical_pull slot has a normal eligible
        // candidate and resolves normally (filled) every week.
        final verticalPullId = await insertExercise(
          slug: 'vp-filler-explanations',
          name: 'Vertical Pull Filler',
          primaryMuscle: 'Lats',
          movementPattern: 'vertical_pull',
        );
        final bicepId = await insertExercise(
          slug: 'bicep-filler-explanations',
          name: 'Bicep Filler',
          primaryMuscle: 'Biceps',
          mechanics: 'isolation',
        );
        final rearId = await insertExercise(
          slug: 'rear-filler-explanations',
          name: 'Rear Delt Filler',
          primaryMuscle: 'Rear Delts',
          mechanics: 'isolation',
        );

        final plan = SplitTemplates.generate(
          type: SplitType.custom,
          daysPerWeek: 1,
          customSlots: const ['Pull Day'],
        );
        final programId = await ProgramsRepository(
          fixtureDb,
        ).createProgramFromSplit(
          name: 'Explanations fixture',
          weeks: 3,
          plan: plan,
          startDate: DateTime(2026, 9, 7),
          buildMode: ProgramBuildMode.smart,
          trainingGoal: TrainingGoal.hypertrophy,
          experienceLevel: ExperienceLevel.novice,
        );
        await SmartProgramPlanner(fixtureDb).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.novice,
          ),
        );

        final allSlots =
            await (fixtureDb.select(fixtureDb.programExerciseSlots)
                  ..where((t) => t.programId.equals(programId))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();
        // Five slot needs on a Pull Day layout (main, supplemental,
        // accessory, isolation, isolation); every one — filled or empty —
        // must have a stable ProgramExerciseSlots row.
        expect(allSlots, hasLength(5));

        final emptySlot = allSlots.firstWhere((s) => s.orderIndex == 0);
        final filledSlot = allSlots.firstWhere((s) => s.orderIndex == 1);

        final emptyExplanations =
            await (fixtureDb.select(fixtureDb.programSlotExplanations)
                  ..where((t) => t.slotId.equals(emptySlot.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
                .get();
        expect(emptyExplanations, hasLength(3));
        expect(emptyExplanations.every((e) => e.status == 'empty'), isTrue);
        expect(
          emptyExplanations.every((e) => e.chosenExerciseId == null),
          isTrue,
        );
        final emptyRationale = emptyExplanations.first.rationale;
        expect(emptyRationale, isNotEmpty);
        expect(
          emptyExplanations.every((e) => e.rationale == emptyRationale),
          isTrue,
        );

        final filledExplanations =
            await (fixtureDb.select(fixtureDb.programSlotExplanations)
                  ..where((t) => t.slotId.equals(filledSlot.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
                .get();
        expect(filledExplanations, hasLength(3));
        expect(filledExplanations.every((e) => e.status == 'filled'), isTrue);

        final filledRotationByWeek = {
          for (final assignment
              in await (fixtureDb.select(fixtureDb.rotationAssignments)
                    ..where((t) => t.slotId.equals(filledSlot.id)))
                  .get())
            assignment.weekIndex: assignment,
        };
        for (final explanation in filledExplanations) {
          final rotation = filledRotationByWeek[explanation.weekIndex]!;
          expect(explanation.chosenExerciseId, rotation.exerciseId);
          expect(explanation.chosenExerciseId, verticalPullId);
        }

        // Every ProgramExerciseSlots row (filled or empty) produces exactly
        // one ProgramSlotExplanations row per week — no gaps, no
        // duplicates.
        final totalExplanations =
            await (fixtureDb.select(fixtureDb.programSlotExplanations)
                  ..where(
                    (t) => t.slotId.isIn(allSlots.map((s) => s.id)),
                  ))
                .get();
        expect(totalExplanations, hasLength(allSlots.length * 3));

        // Every other slot on the day still resolved normally.
        final day = await (fixtureDb.select(
          fixtureDb.programDays,
        )..limit(1)).getSingle();
        final exercises = await (fixtureDb.select(
          fixtureDb.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        final byOrder = {for (final e in exercises) e.orderIndex: e};
        expect(byOrder.containsKey(0), isFalse);
        expect(byOrder[1]!.exerciseId, verticalPullId);
        expect(byOrder[2]!.exerciseId, horizontalPullAccessoryId);
        expect(byOrder[3]!.exerciseId, bicepId);
        expect(byOrder[4]!.exerciseId, rearId);
      },
    );
  });

  group('anchor lock broken by a newly-injury-excluded exercise (Task 2, D-12)', () {
    // Same real-catalog-seeding caveat and zero-equipment-gym isolation
    // trick as the Task 2/3 groups above.
    late AppDatabase fixtureDb;
    setUp(() async {
      fixtureDb = await openTestDatabase();
      await fixtureDb
          .into(fixtureDb.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
    });
    tearDown(() => fixtureDb.close());

    Future<int> insertExercise({
      required String slug,
      required String name,
      required String primaryMuscle,
      String? movementPattern,
      String mechanics = 'compound',
      String modality = 'barbell',
      int cnsScore = 3,
    }) => fixtureDb
        .into(fixtureDb.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            slug: Value(slug),
            name: name,
            primaryMuscle: primaryMuscle,
            equipment: modality,
            mechanics: mechanics,
            force: 'push',
            plane: 'none',
            movementPattern: Value(movementPattern),
            modality: Value(modality),
            cnsScore: Value(cnsScore),
            programmingDifficulty: const Value('novice'),
            programmingCommonness: const Value('basic'),
            allowedTrainingStyles: const Value('["weightlifting"]'),
            technicalEligibility: const Value('automatic'),
            requiredEquipmentKeys: const Value('[]'),
          ),
        );

    Future<int> createPullDayProgram() {
      final plan = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 1,
        customSlots: const ['Pull Day'],
      );
      return ProgramsRepository(fixtureDb).createProgramFromSplit(
        name: 'Anchor break fixture',
        weeks: 3,
        plan: plan,
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.hypertrophy,
        experienceLevel: ExperienceLevel.novice,
      );
    }

    test(
      'regenerating after a new muscle exclusion re-locks a different, '
      'safe exercise instead of keeping the now-unsafe anchor',
      () async {
        // Two candidates eligible for SlotRole.main on the same pattern
        // (cnsScore >= 5 with a max-effort-capable modality), so whichever
        // the scorer ranks first becomes the initial anchor and the other
        // remains available once the first is excluded. Every filler below
        // keeps the default cnsScore of 3 so it never also qualifies for
        // SlotRole.main and pollutes the two-candidate pool.
        final candidateAId = await insertExercise(
          slug: 'pull-candidate-a',
          name: 'Pull Candidate A',
          primaryMuscle: 'Lats',
          movementPattern: 'horizontal_pull',
          cnsScore: 5,
        );
        final candidateBId = await insertExercise(
          slug: 'pull-candidate-b',
          name: 'Pull Candidate B',
          primaryMuscle: 'Traps',
          movementPattern: 'horizontal_pull',
          cnsScore: 5,
        );
        final verticalPullId = await insertExercise(
          slug: 'vertical-pull-filler-3',
          name: 'Vertical Pull Filler',
          primaryMuscle: 'Rhomboids',
          movementPattern: 'vertical_pull',
        );
        final horizontalPullAccessoryId = await insertExercise(
          slug: 'horizontal-pull-accessory-filler-3',
          name: 'Horizontal Pull Accessory Filler',
          primaryMuscle: 'Back',
          movementPattern: 'horizontal_pull',
        );
        final bicepId = await insertExercise(
          slug: 'bicep-filler-3',
          name: 'Bicep Filler',
          primaryMuscle: 'Biceps',
          mechanics: 'isolation',
        );
        final rearId = await insertExercise(
          slug: 'rear-filler-3',
          name: 'Rear Delt Filler',
          primaryMuscle: 'Rear Delts',
          mechanics: 'isolation',
        );

        Future<int> mainSlotIdForCurrentRun() async {
          final day = await (fixtureDb.select(
            fixtureDb.programDays,
          )..limit(1)).getSingle();
          final exercises = await (fixtureDb.select(
            fixtureDb.programDayExercises,
          )..where((t) => t.programDayId.equals(day.id))).get();
          return exercises
              .firstWhere((e) => e.slotRole == SlotRole.main.id)
              .programExerciseSlotId!;
        }

        final programId = await createPullDayProgram();
        await SmartProgramPlanner(fixtureDb).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.novice,
          ),
        );

        final firstSlotId = await mainSlotIdForCurrentRun();
        final firstAssignments =
            await (fixtureDb.select(fixtureDb.rotationAssignments)
                  ..where((t) => t.slotId.equals(firstSlotId)))
                .get();
        expect(
          firstAssignments.map((a) => a.exerciseId).toSet().length,
          1,
          reason: 'the first generation already locks the main slot',
        );
        final firstExerciseId = firstAssignments.first.exerciseId;
        expect({candidateAId, candidateBId}, contains(firstExerciseId));
        final firstExercise = await (fixtureDb.select(
          fixtureDb.exerciseCatalog,
        )..where((t) => t.id.equals(firstExerciseId))).getSingle();

        // Regenerate on the SAME programId with the first exercise's muscle
        // now injury-excluded — no exception should be thrown, and the hard
        // filter must win over the stale lock.
        await SmartProgramPlanner(fixtureDb).populate(
          programId,
          SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.novice,
            excludedMuscles: {firstExercise.primaryMuscle},
          ),
        );

        final secondSlotId = await mainSlotIdForCurrentRun();
        final secondAssignments =
            await (fixtureDb.select(fixtureDb.rotationAssignments)
                  ..where((t) => t.slotId.equals(secondSlotId))
                  ..orderBy([
                    (t) => OrderingTerm(expression: t.weekIndex),
                  ]))
                .get();
        expect(
          secondAssignments.map((a) => a.exerciseId).toSet(),
          isNot(contains(firstExerciseId)),
          reason:
              'the now-unsafe first anchor must never reappear once its '
              'muscle is excluded',
        );
        expect(
          secondAssignments.map((a) => a.exerciseId).toSet().length,
          1,
          reason:
              'the regenerated block must still lock to a single exercise '
              'across all weeks — just a new, safe one',
        );
        final theOtherCandidate = firstExerciseId == candidateAId
            ? candidateBId
            : candidateAId;
        expect(secondAssignments.first.exerciseId, theOtherCandidate);

        // Sanity: the filler slots for the other roles are still present.
        final day = await (fixtureDb.select(
          fixtureDb.programDays,
        )..limit(1)).getSingle();
        final secondRunExercises = await (fixtureDb.select(
          fixtureDb.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        expect(
          secondRunExercises.map((e) => e.exerciseId),
          containsAll([verticalPullId, horizontalPullAccessoryId, bicepId, rearId]),
        );
      },
    );
  });
}
