import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'accessory_seed.dart';
import 'exercise_importer.dart';
import 'exercise_merge.dart';
import 'exercise_merges.dart';
import '../../features/nutrition/data/food_catalogue_importer.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    ExerciseCatalog,
    ExerciseMuscles,
    ExerciseAliases,
    WorkoutSessions,
    WorkoutExercises,
    SetEntries,
    Foods,
    Recipes,
    RecipeIngredients,
    FoodEntries,
    DailySummaries,
    FastingSessions,
    Programs,
    ProgramWeeks,
    ProgramDays,
    ProgramDayExercises,
    ScheduledWorkouts,
    ExternalEvents,
    HealthSamples,
    CycleLogs,
    CycleSettings,
    PendingSyncOps,
    WorkoutFolders,
    WorkoutTemplates,
    TemplateExercises,
    TemplateSets,
    Gyms,
    Accessories,
    Bands,
    SetAccessories,
    SetBands,
    MachineSettings,
    BodyMeasurements,
    ProgressPhotos,
    ExerciseRotations,
    RotationMembers,
    MicroWorkouts,
    ExerciseProgressions,
    FoodMicros,
    FoodCatalogueMeta,
    NutritionTargets,
    DietSchedules,
    CarbCyclePlans,
  ],
)
class AppDatabase extends _$AppDatabase {
  final bool seedFoodCatalogue;

  AppDatabase() : seedFoodCatalogue = true, super(_open());
  AppDatabase.forTesting(super.executor) : seedFoodCatalogue = false;

  @override
  int get schemaVersion => 21;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await ExerciseImporter.runFromAsset(this);
      await AccessorySeed.run(this);
      if (seedFoodCatalogue) {
        await FoodCatalogueImporter.runIfNeeded(this);
      }
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(foods);
        await m.createTable(recipes);
        await m.createTable(recipeIngredients);
        await m.createTable(foodEntries);
        await m.createTable(dailySummaries);
      }
      if (from < 3) {
        await m.createTable(fastingSessions);
      }
      if (from < 4) {
        await m.createTable(programs);
        await m.createTable(programWeeks);
        await m.createTable(programDays);
        await m.createTable(programDayExercises);
        await m.createTable(scheduledWorkouts);
        await m.createTable(externalEvents);
      }
      if (from < 5) {
        await m.createTable(healthSamples);
      }
      if (from < 6) {
        await m.createTable(cycleLogs);
        await m.createTable(cycleSettings);
      }
      if (from < 7) {
        await m.createTable(pendingSyncOps);
      }
      if (from < 8) {
        // Exercise Intelligence: enrich ExerciseCatalog + normalized tables.
        await m.addColumn(exerciseCatalog, exerciseCatalog.aka);
        await m.addColumn(exerciseCatalog, exerciseCatalog.category);
        await m.addColumn(exerciseCatalog, exerciseCatalog.movementPattern);
        await m.addColumn(exerciseCatalog, exerciseCatalog.movementPatternRaw);
        await m.addColumn(exerciseCatalog, exerciseCatalog.modality);
        await m.addColumn(exerciseCatalog, exerciseCatalog.cnsScore);
        await m.addColumn(exerciseCatalog, exerciseCatalog.recoveryImpact);
        await m.addColumn(exerciseCatalog, exerciseCatalog.loggingMetric);
        await m.addColumn(
          exerciseCatalog,
          exerciseCatalog.supportsWeightedBodyweight,
        );
        await m.addColumn(exerciseCatalog, exerciseCatalog.attachments);
        await m.addColumn(exerciseCatalog, exerciseCatalog.isReviewed);
        await m.createTable(exerciseMuscles);
        await m.createTable(exerciseAliases);
        await ExerciseImporter.runFromAsset(this);
      }
      if (from < 9) {
        await m.createTable(workoutFolders);
        await m.createTable(workoutTemplates);
        await m.createTable(templateExercises);
      }
      if (from < 10) {
        // V2 logging foundation: gyms, accessories, bands, set variants,
        // machine configs, body measurements, progress photos.
        await m.createTable(gyms);
        await m.createTable(accessories);
        await m.createTable(bands);
        await m.createTable(setAccessories);
        await m.createTable(setBands);
        await m.createTable(machineSettings);
        await m.createTable(bodyMeasurements);
        await m.createTable(progressPhotos);
        await m.addColumn(workoutSessions, workoutSessions.gymId);
        await m.addColumn(workoutExercises, workoutExercises.equipmentVariant);
        await m.addColumn(workoutExercises, workoutExercises.machineConfigJson);
        await m.addColumn(setEntries, setEntries.setType);
        await m.addColumn(setEntries, setEntries.setTypeMetaJson);
        await m.addColumn(setEntries, setEntries.bodyweightKg);
        await m.addColumn(setEntries, setEntries.chainsKg);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_set_accessories_set '
          'ON set_accessories (set_entry_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_set_bands_set '
          'ON set_bands (set_entry_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_body_measurements_date '
          'ON body_measurements (date_iso, metric)',
        );
        await AccessorySeed.run(this);
      }
      if (from < 11) {
        // Periodization, rotation, micro workouts, progression overrides.
        await m.createTable(exerciseRotations);
        await m.createTable(rotationMembers);
        await m.createTable(microWorkouts);
        await m.createTable(exerciseProgressions);
        await m.addColumn(programs, programs.periodizationModel);
        await m.addColumn(programWeeks, programWeeks.blockPhase);
        await m.addColumn(programWeeks, programWeeks.intensityFactor);
        await m.addColumn(programDayExercises, programDayExercises.rotationId);
        await m.addColumn(programDayExercises, programDayExercises.setType);
        await m.addColumn(
          programDayExercises,
          programDayExercises.percentOf1Rm,
        );
        await m.addColumn(
          programDayExercises,
          programDayExercises.equipmentVariant,
        );
        await m.addColumn(workoutSessions, workoutSessions.microWorkoutId);
      }
      if (from < 12) {
        // Nutrition expansion: micros, day-specific targets, diet
        // automation, carb cycling.
        await m.addColumn(foods, foods.sodiumMgPer100g);
        await m.addColumn(foods, foods.potassiumMgPer100g);
        await m.addColumn(foods, foods.cholesterolMgPer100g);
        await m.createTable(foodMicros);
        await m.createTable(nutritionTargets);
        await m.createTable(dietSchedules);
        await m.createTable(carbCyclePlans);
      }
      if (from < 13) {
        // Collapsed exercise picker: movement-family grouping key, backfilled
        // by re-importing the catalog (computes it in the importer).
        await m.addColumn(exerciseCatalog, exerciseCatalog.movementFamily);
        await ExerciseImporter.runFromAsset(this);
      }
      if (from < 14) {
        await m.addColumn(workoutSessions, workoutSessions.name);
      }
      if (from < 15) {
        await m.addColumn(foods, foods.catalogueId);
        await m.addColumn(foods, foods.referenceBasis);
        await m.addColumn(foods, foods.servingAmount);
        await m.addColumn(foods, foods.servingUnit);
        await m.addColumn(foods, foods.category);
        await m.addColumn(foods, foods.country);
        await m.addColumn(foods, foods.sourceMetadataJson);
        await m.createTable(foodCatalogueMeta);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_foods_catalogue_barcode '
          'ON foods (barcode)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_foods_catalogue_name '
          'ON foods (name COLLATE NOCASE)',
        );
        if (seedFoodCatalogue) {
          await FoodCatalogueImporter.runIfNeeded(this);
        }
      }
      if (from < 16) {
        await m.addColumn(foodEntries, foodEntries.portionAmount);
        await m.addColumn(foodEntries, foodEntries.portionUnit);
      }
      if (from < 17) {
        // Stable exercise identity. Until now the importer matched catalog
        // rows by name, so renaming an exercise inserted a second row and
        // silently orphaned every logged set pointing at the old one. This
        // bootstrap pass is the last one that matches on name — it is safe
        // because no rename has shipped yet, so JSON names still equal the
        // names already in the database.
        await m.addColumn(exerciseCatalog, exerciseCatalog.slug);
        await ExerciseImporter.runFromAsset(this);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_exercise_catalog_slug '
          'ON exercise_catalog (slug) WHERE slug IS NOT NULL',
        );
        await _logOrphanedExerciseReferences();
      }
      if (from < 18) {
        // Movement layer: groups equipment variants in the picker and defines
        // which equipment swaps each exercise actually supports. Backfilled by
        // re-importing, which joins assets/data/movements.json.
        await m.addColumn(exerciseCatalog, exerciseCatalog.movementSlug);
        await m.addColumn(exerciseCatalog, exerciseCatalog.allowedEquipment);
        await ExerciseImporter.runFromAsset(this);
      }
      if (from < 19) {
        // Catalog cleanup. The duplicate rows this folds away are already gone
        // from the JSON asset, but the importer only ever inserts and updates —
        // so on an existing install they would linger in the picker with their
        // logged sets stranded on them. Merge first, then import: the corrected
        // equipment, renames and new rows all arrive with the re-import.
        await ExerciseMergeEngine(this).apply(kExerciseMerges);
        await ExerciseImporter.runFromAsset(this);
      }
      if (from < 20) {
        await m.createTable(templateSets);
      }
      if (from < 21) {
        // Training Blocks rework: splits, rotating cycles, live template links
        // and explicit ordering. Every column is nullable or defaulted, and the
        // four FK-bearing ones are nullable with no default — SQLite only
        // accepts ADD COLUMN ... REFERENCES when the default is NULL.
        await m.addColumn(programs, programs.splitType);
        await m.addColumn(programs, programs.scheduleMode);
        await m.addColumn(programs, programs.cycleLength);
        await m.addColumn(programs, programs.daysPerWeek);
        await m.addColumn(programs, programs.startDateIso);
        await m.addColumn(programs, programs.isActive);

        await m.addColumn(programDays, programDays.templateId);
        await m.addColumn(programDays, programDays.orderIndex);
        await m.addColumn(programDays, programDays.slotLabel);
        await m.addColumn(programDays, programDays.cycleDayIndex);
        await m.addColumn(programDays, programDays.isRest);

        await m.addColumn(scheduledWorkouts, scheduledWorkouts.programId);
        await m.addColumn(scheduledWorkouts, scheduledWorkouts.orderIndex);
        await m.addColumn(scheduledWorkouts, scheduledWorkouts.occurrenceIndex);
        await m.addColumn(
          scheduledWorkouts,
          scheduledWorkouts.templateIdOverride,
        );

        // ── Backfill ──
        // Owning program for every existing scheduled row.
        await customStatement('''
          UPDATE scheduled_workouts SET program_id = (
            SELECT pw.program_id FROM program_days pd
            JOIN program_weeks pw ON pw.id = pd.program_week_id
            WHERE pd.id = scheduled_workouts.program_day_id)
        ''');
        // Dense order within each date, stable by insertion id.
        await customStatement('''
          UPDATE scheduled_workouts SET order_index = (
            SELECT COUNT(*) FROM scheduled_workouts s2
            WHERE s2.date_iso = scheduled_workouts.date_iso
              AND s2.id < scheduled_workouts.id)
        ''');
        // Occurrence index = how many earlier dates the same program day
        // already produced. Exact for both legacy block and rotating programs.
        await customStatement('''
          UPDATE scheduled_workouts SET occurrence_index = (
            SELECT COUNT(DISTINCT s2.date_iso) FROM scheduled_workouts s2
            WHERE s2.program_day_id = scheduled_workouts.program_day_id
              AND s2.date_iso < scheduled_workouts.date_iso)
        ''');
        // Dense order for program days sharing a weekday.
        await customStatement('''
          UPDATE program_days SET order_index = (
            SELECT COUNT(*) FROM program_days d2
            WHERE d2.program_week_id = program_days.program_week_id
              AND d2.day_of_week = program_days.day_of_week
              AND d2.id < program_days.id)
        ''');
        // Seed the split slot label from the existing free-text day name.
        await customStatement(
          'UPDATE program_days SET slot_label = name WHERE slot_label IS NULL',
        );
        // Anchor date per program, and the one active block: whichever
        // non-archived program owns the latest scheduled date.
        await customStatement('''
          UPDATE programs SET start_date_iso = (
            SELECT MIN(sw.date_iso) FROM scheduled_workouts sw
            WHERE sw.program_id = programs.id)
        ''');
        await customStatement('''
          UPDATE programs SET is_active = 1 WHERE id = (
            SELECT sw.program_id FROM scheduled_workouts sw
            JOIN programs p ON p.id = sw.program_id
            WHERE p.archived = 0 AND sw.program_id IS NOT NULL
            ORDER BY sw.date_iso DESC LIMIT 1)
        ''');
      }
    },
  );

  /// Counts rows in every table referencing [ExerciseCatalog] whose exercise
  /// no longer exists.
  ///
  /// Foreign keys have never been enforced in production (there is no
  /// `beforeOpen` pragma), so historic importer name-churn may have left
  /// dangling ids. Enabling enforcement before those are repaired would turn
  /// them into a crash on open, so this only reports — see the deferred FK
  /// enforcement step.
  Future<void> _logOrphanedExerciseReferences() async {
    const referencingTables = <String>[
      'workout_exercises',
      'program_day_exercises',
      'rotation_members',
      'micro_workouts',
      'exercise_progressions',
      'machine_settings',
      'template_exercises',
    ];
    for (final table in referencingTables) {
      try {
        final rows = await customSelect(
          'SELECT COUNT(*) AS c FROM $table '
          'WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)',
        ).get();
        final count = rows.first.read<int>('c');
        if (count > 0) {
          // ignore: avoid_print
          print('Migration v17: $count orphaned exercise_id in $table');
        }
      } catch (_) {
        // Table may not exist on very old schemas; nothing to report.
      }
    }
  }
}

QueryExecutor _open() => driftDatabase(name: 'herculex');
