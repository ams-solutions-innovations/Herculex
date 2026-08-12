import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/rotations_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workouts/data/micro_workouts_repository.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  final DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

/// Phase 1 of RB-04: every delete path below is hardened to be explicitly
/// transactional and child-first, mirroring what the declared cascade would
/// do — independent of whether `PRAGMA foreign_keys` is on. Each "identical
/// under both pragma settings" test is the literal proof of that claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Row id of any exercise from the seeded catalog — the catalog is
  /// populated by `onCreate`, so no fixture insert is needed for it.
  Future<int> anyExerciseId(AppDatabase db) async {
    final row = await (db.select(db.exerciseCatalog)..limit(1)).getSingle();
    return row.id;
  }

  Future<int> insertAccessory(AppDatabase db) => db
      .into(db.accessories)
      .insert(AccessoriesCompanion.insert(name: 'Belt', kind: 'belt'));

  Future<int> insertBand(AppDatabase db) => db.into(db.bands).insert(
    BandsCompanion.insert(name: 'Red band', color: 'red', tensionKg: 20),
  );

  group('deleteSession', () {
    Future<
      ({
        int sessionId,
        int weId,
        int setId,
        int scheduleId,
        int programDayId,
      })
    >
    buildTree(AppDatabase db) async {
      final exerciseId = await anyExerciseId(db);
      final accessoryId = await insertAccessory(db);
      final bandId = await insertBand(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
            ),
          );
      await db
          .into(db.setAccessories)
          .insert(
            SetAccessoriesCompanion.insert(
              setEntryId: setId,
              accessoryId: accessoryId,
            ),
          );
      await db
          .into(db.setBands)
          .insert(
            SetBandsCompanion.insert(setEntryId: setId, bandId: bandId),
          );

      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final programDayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Day 1',
            ),
          );
      final scheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-01',
              programDayId: programDayId,
              completedSessionId: Value(sessionId),
              status: const Value(ScheduleStatus.done),
            ),
          );

      return (
        sessionId: sessionId,
        weId: weId,
        setId: setId,
        scheduleId: scheduleId,
        programDayId: programDayId,
      );
    }

    test('removes the whole subtree and resets the schedule off done', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = WorkoutsRepository(db, const SystemClock());
      final tree = await buildTree(db);

      await repo.deleteSession(tree.sessionId);

      expect(await db.select(db.workoutSessions).get(), isEmpty);
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.setEntries).get(), isEmpty);
      expect(await db.select(db.setAccessories).get(), isEmpty);
      expect(await db.select(db.setBands).get(), isEmpty);

      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(tree.scheduleId))).getSingle();
      expect(schedule.completedSessionId, isNull);
      expect(schedule.status, ScheduleStatus.planned);

      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });

    test('is identical whether FKs are on or off', () async {
      final dbOn = await openTestDatabase();
      final dbOff = await openTestDatabase(foreignKeys: false);
      addTearDown(dbOn.close);
      addTearDown(dbOff.close);

      final treeOn = await buildTree(dbOn);
      final treeOff = await buildTree(dbOff);

      await WorkoutsRepository(dbOn, const SystemClock())
          .deleteSession(treeOn.sessionId);
      await WorkoutsRepository(dbOff, const SystemClock())
          .deleteSession(treeOff.sessionId);

      expect(
        await dbCount(dbOn, 'workout_sessions'),
        await dbCount(dbOff, 'workout_sessions'),
      );
      expect(
        await dbCount(dbOn, 'workout_exercises'),
        await dbCount(dbOff, 'workout_exercises'),
      );
      expect(
        await dbCount(dbOn, 'set_entries'),
        await dbCount(dbOff, 'set_entries'),
      );
      expect(
        await dbCount(dbOn, 'set_accessories'),
        await dbCount(dbOff, 'set_accessories'),
      );
      expect(
        await dbCount(dbOn, 'set_bands'),
        await dbCount(dbOff, 'set_bands'),
      );
      expect(
        await dbCount(dbOn, 'scheduled_workouts'),
        await dbCount(dbOff, 'scheduled_workouts'),
      );
    });
  });

  group('removeWorkoutExercise', () {
    test('clears set children before the exercise', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final accessoryId = await insertAccessory(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
            ),
          );
      await db
          .into(db.setAccessories)
          .insert(
            SetAccessoriesCompanion.insert(
              setEntryId: setId,
              accessoryId: accessoryId,
            ),
          );

      await WorkoutsRepository(
        db,
        const SystemClock(),
      ).removeWorkoutExercise(weId);

      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.setEntries).get(), isEmpty);
      expect(await db.select(db.setAccessories).get(), isEmpty);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('deleteSet', () {
    test('clears accessories/bands before the set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final accessoryId = await insertAccessory(db);
      final bandId = await insertBand(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
            ),
          );
      await db
          .into(db.setAccessories)
          .insert(
            SetAccessoriesCompanion.insert(
              setEntryId: setId,
              accessoryId: accessoryId,
            ),
          );
      await db
          .into(db.setBands)
          .insert(
            SetBandsCompanion.insert(setEntryId: setId, bandId: bandId),
          );

      await WorkoutsRepository(db, const SystemClock()).deleteSet(setId);

      expect(await db.select(db.setEntries).get(), isEmpty);
      expect(await db.select(db.setAccessories).get(), isEmpty);
      expect(await db.select(db.setBands).get(), isEmpty);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('deleteProgram', () {
    Future<
      ({
        int programId,
        int weekId,
        int dayId,
        int dayExerciseId,
        int scheduleByProgram,
        int scheduleByDay,
      })
    >
    buildTree(AppDatabase db) async {
      final exerciseId = await anyExerciseId(db);
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
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
              name: 'Day 1',
            ),
          );
      final dayExerciseId = await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      // Two distinct CASCADE edges into scheduled_workouts: one row that
      // only points back via programId, one only via programDayId.
      final scheduleByProgram = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-01',
              programDayId: dayId,
              programId: const Value(null),
            ),
          );
      final scheduleByDay = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-02',
              programDayId: dayId,
              programId: Value(programId),
            ),
          );
      return (
        programId: programId,
        weekId: weekId,
        dayId: dayId,
        dayExerciseId: dayExerciseId,
        scheduleByProgram: scheduleByProgram,
        scheduleByDay: scheduleByDay,
      );
    }

    test('removes the whole program tree, both schedule edges included', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final tree = await buildTree(db);

      await ProgramsRepository(db).deleteProgram(tree.programId);

      expect(await db.select(db.programs).get(), isEmpty);
      expect(await db.select(db.programWeeks).get(), isEmpty);
      expect(await db.select(db.programDays).get(), isEmpty);
      expect(await db.select(db.programDayExercises).get(), isEmpty);
      expect(await db.select(db.scheduledWorkouts).get(), isEmpty);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });

    test('is identical whether FKs are on or off', () async {
      final dbOn = await openTestDatabase();
      final dbOff = await openTestDatabase(foreignKeys: false);
      addTearDown(dbOn.close);
      addTearDown(dbOff.close);

      final treeOn = await buildTree(dbOn);
      final treeOff = await buildTree(dbOff);

      await ProgramsRepository(dbOn).deleteProgram(treeOn.programId);
      await ProgramsRepository(dbOff).deleteProgram(treeOff.programId);

      for (final table in [
        'programs',
        'program_weeks',
        'program_days',
        'program_day_exercises',
        'scheduled_workouts',
      ]) {
        expect(await dbCount(dbOn, table), await dbCount(dbOff, table));
      }
    });
  });

  group('deleteProgramDay', () {
    test('removes day exercises and schedules first', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
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
              name: 'Day 1',
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-01',
              programDayId: dayId,
            ),
          );

      await ProgramsRepository(db).deleteProgramDay(dayId);

      expect(await db.select(db.programDays).get(), isEmpty);
      expect(await db.select(db.programDayExercises).get(), isEmpty);
      expect(await db.select(db.scheduledWorkouts).get(), isEmpty);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('deleteRotation', () {
    test('removes members and nulls the program day exercise link', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
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
              name: 'Day 1',
            ),
          );
      final rotationId = await db
          .into(db.exerciseRotations)
          .insert(ExerciseRotationsCompanion.insert(name: 'Rotation'));
      await db
          .into(db.rotationMembers)
          .insert(
            RotationMembersCompanion.insert(
              rotationId: rotationId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final dayExerciseId = await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
              rotationId: Value(rotationId),
            ),
          );

      await RotationsRepository(db).deleteRotation(rotationId);

      expect(await db.select(db.exerciseRotations).get(), isEmpty);
      expect(await db.select(db.rotationMembers).get(), isEmpty);
      final dayExercise = await (db.select(
        db.programDayExercises,
      )..where((t) => t.id.equals(dayExerciseId))).getSingle();
      expect(dayExercise.rotationId, isNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('templates', () {
    test('deleteTemplate clears sets, exercises, and unlinks referrers', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);

      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'T'));
      final templateExerciseId = await db
          .into(db.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      await db
          .into(db.templateSets)
          .insert(
            TemplateSetsCompanion.insert(
              templateExerciseId: templateExerciseId,
              setOrder: 1,
            ),
          );

      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
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
              name: 'Day 1',
              templateId: Value(templateId),
            ),
          );
      final scheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-01',
              programDayId: dayId,
              templateIdOverride: Value(templateId),
            ),
          );

      await TemplatesRepository(db).deleteTemplate(templateId);

      expect(await db.select(db.workoutTemplates).get(), isEmpty);
      expect(await db.select(db.templateExercises).get(), isEmpty);
      expect(await db.select(db.templateSets).get(), isEmpty);

      final day = await (db.select(
        db.programDays,
      )..where((t) => t.id.equals(dayId))).getSingle();
      expect(day.templateId, isNull);
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(scheduleId))).getSingle();
      expect(schedule.templateIdOverride, isNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });

    test('deleteFolder nulls the folder link on its templates', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final folderId = await db
          .into(db.workoutFolders)
          .insert(WorkoutFoldersCompanion.insert(name: 'Folder'));
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(
            WorkoutTemplatesCompanion.insert(
              name: 'T',
              folderId: Value(folderId),
            ),
          );

      await TemplatesRepository(db).deleteFolder(folderId);

      expect(await db.select(db.workoutFolders).get(), isEmpty);
      final template = await (db.select(
        db.workoutTemplates,
      )..where((t) => t.id.equals(templateId))).getSingle();
      expect(template.folderId, isNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });

    test('removeExerciseFromTemplate clears its sets first', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'T'));
      final templateExerciseId = await db
          .into(db.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      await db
          .into(db.templateSets)
          .insert(
            TemplateSetsCompanion.insert(
              templateExerciseId: templateExerciseId,
              setOrder: 1,
            ),
          );

      await TemplatesRepository(
        db,
      ).removeExerciseFromTemplate(templateExerciseId);

      expect(await db.select(db.templateExercises).get(), isEmpty);
      expect(await db.select(db.templateSets).get(), isEmpty);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('deleteGym', () {
    test('nulls sessions and machine settings before the gym', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final gymId = await db
          .into(db.gyms)
          .insert(GymsCompanion.insert(name: 'Gym'));
      final sessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: DateTime(2026),
              gymId: Value(gymId),
            ),
          );
      final settingsId = await db
          .into(db.machineSettings)
          .insert(
            MachineSettingsCompanion.insert(
              exerciseId: exerciseId,
              gymId: Value(gymId),
              settingsJson: '{}',
            ),
          );

      await GymsRepository(db).deleteGym(gymId);

      expect(await db.select(db.gyms).get(), isEmpty);
      final session = await (db.select(
        db.workoutSessions,
      )..where((t) => t.id.equals(sessionId))).getSingle();
      expect(session.gymId, isNull);
      final settings = await (db.select(
        db.machineSettings,
      )..where((t) => t.id.equals(settingsId))).getSingle();
      expect(settings.gymId, isNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('MicroWorkoutsRepository.delete', () {
    test('nulls the session link before deleting', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);
      final microId = await db
          .into(db.microWorkouts)
          .insert(
            MicroWorkoutsCompanion.insert(
              name: 'Pushups',
              exerciseId: exerciseId,
              targetReps: 20,
            ),
          );
      final sessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: DateTime(2026),
              microWorkoutId: Value(microId),
            ),
          );

      await MicroWorkoutsRepository(
        db,
        const SystemClock(),
      ).delete(microId);

      expect(await db.select(db.microWorkouts).get(), isEmpty);
      final session = await (db.select(
        db.workoutSessions,
      )..where((t) => t.id.equals(sessionId))).getSingle();
      expect(session.microWorkoutId, isNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('NutritionRepository.deleteFood', () {
    Future<int> insertFood(AppDatabase db) async {
      final id = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Chicken', kcalPer100g: 165));
      await db
          .into(db.foodMicros)
          .insert(
            FoodMicrosCompanion.insert(
              foodId: id,
              nutrient: 'Iron',
              amountPer100g: 1,
              unit: 'mg',
            ),
          );
      return id;
    }

    test('soft-deletes: row and food_micros stay, deletedAt is stamped', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final foodId = await insertFood(db);
      final clock = _FixedClock(DateTime(2026, 6, 1));

      await NutritionRepository(
        db,
        OpenFoodFactsClient(),
        clock,
      ).deleteFood(foodId);

      final food = await (db.select(
        db.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.deletedAt, clock.now());
      expect(await db.select(db.foodMicros).get(), hasLength(1));
    });

    test('soft-deletes without throwing when a food_entry references it', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final foodId = await insertFood(db);
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-01-01',
              meal: 'lunch',
              foodId: Value(foodId),
            ),
          );

      await NutritionRepository(
        db,
        OpenFoodFactsClient(),
        const SystemClock(),
      ).deleteFood(foodId);

      final food = await (db.select(
        db.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.deletedAt, isNotNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });

    test('soft-deletes without throwing when a recipe references it', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final foodId = await insertFood(db);
      final recipeId = await db
          .into(db.recipes)
          .insert(RecipesCompanion.insert(name: 'Bowl'));
      await db
          .into(db.recipeIngredients)
          .insert(
            RecipeIngredientsCompanion.insert(
              recipeId: recipeId,
              foodId: foodId,
              grams: 100,
            ),
          );

      await NutritionRepository(
        db,
        OpenFoodFactsClient(),
        const SystemClock(),
      ).deleteFood(foodId);

      final food = await (db.select(
        db.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.deletedAt, isNotNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('NutritionRepository.deleteRecipe', () {
    test('soft-deletes: row and recipe_ingredients stay, deletedAt is stamped', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final foodId = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Rice', kcalPer100g: 130));
      final recipeId = await db
          .into(db.recipes)
          .insert(RecipesCompanion.insert(name: 'Bowl'));
      await db
          .into(db.recipeIngredients)
          .insert(
            RecipeIngredientsCompanion.insert(
              recipeId: recipeId,
              foodId: foodId,
              grams: 100,
            ),
          );
      final clock = _FixedClock(DateTime(2026, 6, 1));

      await NutritionRepository(
        db,
        OpenFoodFactsClient(),
        clock,
      ).deleteRecipe(recipeId);

      final recipe = await (db.select(
        db.recipes,
      )..where((t) => t.id.equals(recipeId))).getSingle();
      expect(recipe.deletedAt, clock.now());
      expect(await db.select(db.recipeIngredients).get(), hasLength(1));
    });

    test('soft-deletes without crashing when a food_entry references it', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final recipeId = await db
          .into(db.recipes)
          .insert(RecipesCompanion.insert(name: 'Bowl'));
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-01-01',
              meal: 'lunch',
              recipeId: Value(recipeId),
            ),
          );

      await NutritionRepository(
        db,
        OpenFoodFactsClient(),
        const SystemClock(),
      ).deleteRecipe(recipeId);

      final recipe = await (db.select(
        db.recipes,
      )..where((t) => t.id.equals(recipeId))).getSingle();
      expect(recipe.deletedAt, isNotNull);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });
}

Future<int> dbCount(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}
