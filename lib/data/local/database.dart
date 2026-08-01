import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'accessory_seed.dart';
import 'exercise_importer.dart';
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
  int get schemaVersion => 16;

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
    },
  );
}

QueryExecutor _open() => driftDatabase(name: 'herculex');
