import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  test(
    'inline Max Effort creates ramp, top set and back-off snapshot',
    () async {
      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Low-Bar Back Squat Test',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              modality: const Value('barbell'),
              movementPattern: const Value('squat'),
              maxEffortEligibility: const Value('suitable'),
            ),
          );
      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: 'Upper Lower',
              trainingGoal: const Value('powerbuilding'),
            ),
          );
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Lower Intensity',
              stressRole: const Value('intensity'),
            ),
          );
      final slotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'lower-main',
              daySlotLabel: 'Lower',
              orderIndex: 0,
              role: Value(SlotRole.main.id),
              movementPattern: const Value('squat'),
              trainingMethod: Value(SlotTrainingMethod.maxEffort.id),
              fatigueBudget: const Value(8),
            ),
          );
      final dayExerciseId = await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
              programExerciseSlotId: Value(slotId),
              slotRole: Value(SlotRole.main.id),
              trainingMethod: Value(SlotTrainingMethod.maxEffort.id),
            ),
          );

      final resolver = PlannedSessionResolver(db);
      final plan = await resolver.resolveProgramDay(dayId);
      expect(plan.exercises.single.trainingMethod, 'max_effort');
      // Max-effort warmups now come from WarmupResolver at a 0.90 target,
      // which is the dense (5-step) ramp for the first heavy lift of the
      // session (D-08/D-10), ahead of the top single + 3 back-off sets.
      expect(plan.exercises.single.sets.where((s) => s.isWarmup), hasLength(5));
      expect(plan.exercises.single.sets, hasLength(9));
      expect(plan.exercises.single.sets[5].repsMin, 1);
      expect(plan.exercises.single.sets[5].repsMax, 3);
      expect(plan.exercises.single.sets[5].rpeX10, 90);

      final sessionId = await resolver.materialize(plan);
      final workoutExercise = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).getSingle();
      final sets =
          await (db.select(db.setEntries)
                ..where((t) => t.workoutExerciseId.equals(workoutExercise.id))
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();
      expect(sets, hasLength(9));
      expect(sets[5].plannedRepsMin, 1);
      expect(sets[5].plannedRepsMax, 3);
      expect(sets[5].plannedRpeX10, 90);
      expect(sets.every((s) => s.reps == 0 && s.weightKg == 0), isTrue);

      // Future plan edits cannot mutate the active workout snapshot.
      await (db.update(db.programDayExercises)
            ..where((t) => t.id.equals(dayExerciseId)))
          .write(const ProgramDayExercisesCompanion(targetRepsMin: Value(10)));
      final frozen =
          await (db.select(db.setEntries)
                ..where((t) => t.workoutExerciseId.equals(workoutExercise.id))
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();
      expect(frozen[5].plannedRepsMin, 1);
    },
  );

  test(
    'new builder snapshots a linked template into an owned blueprint',
    () async {
      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Owned Blueprint Press',
              primaryMuscle: 'Chest',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'horizontal',
            ),
          );
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'Press Template'));
      final templateExerciseId = await db
          .into(db.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: exerciseId,
              orderIndex: 0,
              targetSets: const Value(2),
              targetRepsMin: const Value(6),
              targetRepsMax: const Value(8),
            ),
          );
      await db.batch((batch) {
        batch.insertAll(db.templateSets, [
          TemplateSetsCompanion.insert(
            templateExerciseId: templateExerciseId,
            setOrder: 1,
            targetReps: const Value(5),
            targetWeightKg: const Value(80),
            isWarmup: const Value(true),
          ),
          TemplateSetsCompanion.insert(
            templateExerciseId: templateExerciseId,
            setOrder: 2,
            targetRepsMin: const Value(6),
            targetRepsMax: const Value(8),
            targetWeightKg: const Value(100),
            setType: const Value('pause'),
            setTypeMetaJson: const Value('{"pauseSeconds":2}'),
          ),
        ]);
      });
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Stable Program'));
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Upper',
              templateId: Value(templateId),
            ),
          );

      await ProgramsRepository(db).snapshotLinkedTemplates(programId);
      final day = await (db.select(
        db.programDays,
      )..where((row) => row.id.equals(dayId))).getSingle();
      expect(day.templateId, isNull);

      final firstPlan = await PlannedSessionResolver(
        db,
      ).resolveProgramDay(dayId);
      expect(firstPlan.exercises.single.sets, hasLength(2));
      expect(firstPlan.exercises.single.sets.first.isWarmup, isTrue);
      expect(firstPlan.exercises.single.sets.last.weightKg, 100);
      expect(firstPlan.exercises.single.sets.last.setType, 'pause');

      await (db.update(db.templateSets)
            ..where((row) => row.templateExerciseId.equals(templateExerciseId)))
          .write(const TemplateSetsCompanion(targetWeightKg: Value(20)));
      final unchanged = await PlannedSessionResolver(
        db,
      ).resolveProgramDay(dayId);
      expect(unchanged.exercises.single.sets.last.weightKg, 100);
    },
  );

  test('automatic warm-ups are added only to eligible compound work', () async {
    final exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Warm-up Barbell Press',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
            modality: const Value('barbell'),
          ),
        );
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Warm-up Program'));
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    final dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: weekId,
            dayOfWeek: 1,
            name: 'Upper',
          ),
        );
    await db
        .into(db.programDayExercises)
        .insert(
          ProgramDayExercisesCompanion.insert(
            programDayId: dayId,
            exerciseId: exerciseId,
            orderIndex: 0,
            slotRole: Value(SlotRole.main.id),
            trainingMethod: Value(SlotTrainingMethod.straightSets.id),
            variantConfigJson: const Value('{"autoWarmups":true}'),
          ),
        );

    final sets = (await PlannedSessionResolver(
      db,
    ).resolveProgramDay(dayId)).exercises.single.sets;
    // No explicit %1RM target on this straight-sets slot, so WarmupResolver
    // falls back to its 2-step light ramp (D-08).
    expect(sets.where((set) => set.isWarmup), hasLength(2));
    expect(sets.skip(2).every((set) => !set.isWarmup), isTrue);
    expect(sets.first.percentOf1Rm, .4);
  });

  test(
    'movement order abbreviates warmups for a later heavy lift at the same intensity',
    () async {
      final firstExerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Movement Order Squat',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              modality: const Value('barbell'),
            ),
          );
      final secondExerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Movement Order Row',
              primaryMuscle: 'Back',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'pull',
              plane: 'horizontal',
              modality: const Value('barbell'),
            ),
          );
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Movement Order Program'));
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Full Body',
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: firstExerciseId,
              orderIndex: 0,
              slotRole: Value(SlotRole.main.id),
              trainingMethod: Value(SlotTrainingMethod.straightSets.id),
              percentOf1Rm: const Value(0.80),
              variantConfigJson: const Value('{"autoWarmups":true}'),
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: secondExerciseId,
              orderIndex: 1,
              slotRole: Value(SlotRole.supplemental.id),
              trainingMethod: Value(SlotTrainingMethod.straightSets.id),
              percentOf1Rm: const Value(0.80),
              variantConfigJson: const Value('{"autoWarmups":true}'),
            ),
          );

      final plan = await PlannedSessionResolver(db).resolveProgramDay(dayId);
      final firstWarmups = plan.exercises[0].sets
          .where((s) => s.isWarmup)
          .length;
      final secondWarmups = plan.exercises[1].sets
          .where((s) => s.isWarmup)
          .length;
      expect(firstWarmups, greaterThan(secondWarmups));
    },
  );

  test(
    'linear novice workout session resolves straight sets matching targetSets and never 8x3',
    () async {
      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Novice Squat Test',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              modality: const Value('barbell'),
            ),
          );
      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: 'Novice Linear',
              periodizationModel: const Value('linear'),
              trainingGoal: const Value('strength'),
            ),
          );
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Full Body A',
              stressRole: const Value('intensity'),
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
              slotRole: Value(SlotRole.main.id),
              trainingMethod: Value(SlotTrainingMethod.dynamicEffort.id),
              targetSets: const Value(3),
              targetRepsMin: const Value(5),
              targetRepsMax: const Value(5),
            ),
          );

      final plan = await PlannedSessionResolver(db).resolveProgramDay(dayId);
      final exercise = plan.exercises.single;
      expect(exercise.trainingMethod, 'straight_sets');
      final workSets = exercise.sets.where((s) => !s.isWarmup).toList();
      expect(workSets, hasLength(3));
      expect(workSets.every((s) => s.repsMin == 5 && s.repsMax == 5), isTrue);
      expect(workSets, isNot(hasLength(8)));
    },
  );
}
