import 'dart:developer' show log;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'accessory_seed.dart';
import 'exercise_importer.dart';
import 'exercise_merge.dart';
import 'exercise_merges.dart';
import 'fk_repair.dart';
import 'migrations/nutrition_snapshot_backfill.dart';
import 'migrations/sync_backfill.dart';
import 'migrations/sync_triggers.dart';
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
    SyncCursors,
    // Assisted rep tracking (v26). Local-only: never added to
    // syncedTableNames or syncTableSpecs.
    RepTrackingSettings,
    RepTrackingExercisePrefs,
    RepSetObservations,
    FastingSchedules,
  ],
)
class AppDatabase extends _$AppDatabase {
  final bool seedFoodCatalogue;

  AppDatabase() : seedFoodCatalogue = true, super(_open());
  AppDatabase.forTesting(super.executor) : seedFoodCatalogue = false;

  @override
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await ExerciseImporter.runFromAsset(this);
      await AccessorySeed.run(this);
      if (seedFoodCatalogue) {
        await FoodCatalogueImporter.runIfNeeded(this);
      }
      // A fresh install has no pre-v25 rows to backfill, but still needs the
      // sync_uuid uniqueness guarantee and the outbox triggers — onUpgrade's
      // v25 block only runs for databases that already existed pre-sync.
      for (final tableName in syncedTableNames) {
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_$tableName '
          'ON $tableName(sync_uuid)',
        );
      }
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_sync_ops_entity '
        'ON pending_sync_ops(entity_type, entity_id)',
      );
      await installSyncTriggers(this);
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
      if (from < 22) {
        // Phase 1 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md:
        // stable session identity for the phone<->watch wire protocol.
        await m.addColumn(workoutSessions, workoutSessions.sessionUuid);
        // No Drift/SQLite UUID() function exists, so backfill existing rows
        // one at a time from Dart instead of a single customStatement.
        final existingSessionIds = await customSelect(
          'SELECT id FROM workout_sessions WHERE session_uuid IS NULL',
        ).get();
        for (final row in existingSessionIds) {
          await customUpdate(
            'UPDATE workout_sessions SET session_uuid = ? WHERE id = ?',
            variables: [
              Variable(const Uuid().v4()),
              Variable(row.read<int>('id')),
            ],
            updates: {workoutSessions},
          );
        }
      }
      if (from < 23) {
        // RB-04 Phase 2: repair FK violations before enforcement lands in
        // Phase 3. Runs with foreign_keys OFF — drift migrations are inside
        // a transaction and the pragma lives in beforeOpen. Supersedes the
        // v17 `_logOrphanedExerciseReferences` report-only sweep, which
        // covered only 7 of the 36 declared edges and never fixed anything.
        final report = await repairForeignKeyViolations(this);
        for (final entry in report.nulled.entries) {
          if (entry.value > 0) {
            log('Migration v23: nulled ${entry.value} orphan ${entry.key}');
          }
        }
        for (final entry in report.deleted.entries) {
          if (entry.value > 0) {
            log('Migration v23: deleted ${entry.value} orphan rows from ${entry.key}');
          }
        }
        if (report.residualViolations > 0) {
          log(
            'Migration v23: ${report.residualViolations} FK violations '
            'remain after repair',
          );
        }

        // Every FK child column, for the repair's own NOT IN (...) scans and
        // for cascade/restrict performance once enforcement lands.
        const fkChildColumns = <(String, String)>[
          ('exercise_aliases', 'exercise_id'),
          ('exercise_muscles', 'exercise_id'),
          ('exercise_progressions', 'exercise_id'),
          ('food_entries', 'recipe_id'),
          ('food_entries', 'food_id'),
          ('food_micros', 'food_id'),
          ('machine_settings', 'gym_id'),
          ('machine_settings', 'exercise_id'),
          ('micro_workouts', 'exercise_id'),
          ('program_day_exercises', 'rotation_id'),
          ('program_day_exercises', 'exercise_id'),
          ('program_day_exercises', 'program_day_id'),
          ('program_days', 'template_id'),
          ('program_days', 'program_week_id'),
          ('program_weeks', 'program_id'),
          ('recipe_ingredients', 'food_id'),
          ('recipe_ingredients', 'recipe_id'),
          ('rotation_members', 'exercise_id'),
          ('rotation_members', 'rotation_id'),
          ('scheduled_workouts', 'template_id_override'),
          ('scheduled_workouts', 'program_id'),
          ('scheduled_workouts', 'completed_session_id'),
          ('scheduled_workouts', 'program_day_id'),
          ('set_accessories', 'accessory_id'),
          ('set_bands', 'band_id'),
          ('template_exercises', 'exercise_id'),
          ('template_exercises', 'template_id'),
          ('template_sets', 'template_exercise_id'),
          ('workout_exercises', 'exercise_id'),
          ('workout_exercises', 'session_id'),
          ('workout_sessions', 'micro_workout_id'),
          ('workout_sessions', 'gym_id'),
          ('workout_templates', 'folder_id'),
          // set_accessories.set_entry_id and set_bands.set_entry_id already
          // have indexes from the v10 migration (idx_set_accessories_set,
          // idx_set_bands_set) — not repeated here.
        ];
        for (final (table, column) in fkChildColumns) {
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_fk_${table}_$column '
              'ON $table ($column)',
            );
          } catch (_) {
            // As with repairForeignKeyViolations above: a table this old
            // migration step references may not exist on a hand-rolled test
            // fixture that only stamps down a narrow slice of the schema.
            // Never true on a real device, where every table here was
            // created by an earlier onUpgrade step long before v23.
          }
        }
      }
      if (from < 24) {
        // RB-05: freeze each logged entry's nutrition at log time, and give
        // foods/recipes a soft-delete tombstone so the RESTRICT edges from
        // food_entries and recipe_ingredients stay satisfiable forever.
        // Every column is nullable with no default and none carries a
        // REFERENCES clause, so these are plain ALTER TABLE ADD COLUMNs —
        // no legacy_alter_table rebuild, no FK edge moves.
        //
        // As with the v23 fkChildColumns loop above: foods/recipes/
        // food_entries may not exist on a hand-rolled test fixture that only
        // stamps down a narrow slice of the schema (see
        // test/schema_v21_test.dart, test/fk_repair_test.dart). Never true on
        // a real device, where all three were created by the v2 onUpgrade
        // step long before v24.
        Future<void> tryAddColumn(
          TableInfo<Table, dynamic> table,
          GeneratedColumn column,
        ) async {
          try {
            await m.addColumn(table, column);
          } catch (_) {
            // Table doesn't exist on this fixture; see comment above.
          }
        }

        await tryAddColumn(foods, foods.deletedAt);
        await tryAddColumn(recipes, recipes.deletedAt);
        await tryAddColumn(foodEntries, foodEntries.snapshotBasis);
        await tryAddColumn(foodEntries, foodEntries.snapshotName);
        await tryAddColumn(foodEntries, foodEntries.snapshotBrand);
        await tryAddColumn(foodEntries, foodEntries.snapshotKcal);
        await tryAddColumn(foodEntries, foodEntries.snapshotProteinG);
        await tryAddColumn(foodEntries, foodEntries.snapshotCarbsG);
        await tryAddColumn(foodEntries, foodEntries.snapshotFatG);
        await tryAddColumn(foodEntries, foodEntries.snapshotFiberG);
        await tryAddColumn(foodEntries, foodEntries.snapshotSodiumMg);
        await tryAddColumn(foodEntries, foodEntries.snapshotPotassiumMg);
        await tryAddColumn(foodEntries, foodEntries.snapshotCholesterolMg);
        await tryAddColumn(foodEntries, foodEntries.snapshotServingGrams);
        await tryAddColumn(foodEntries, foodEntries.snapshotServingAmount);
        await tryAddColumn(foodEntries, foodEntries.snapshotServingUnit);
        await tryAddColumn(foodEntries, foodEntries.snapshotMicrosJson);

        try {
          final filled = await backfillNutritionSnapshots(this);
          log(
            'Migration v24: snapshotted ${filled.foodEntries} food and '
            '${filled.recipeEntries} recipe diary entries, '
            '${filled.microsFoods} foods with micronutrients',
          );
        } catch (_) {
          // Same as above: no nutrition tables on this fixture.
        }
      }
      if (from < 25) {
        await m.createTable(syncCursors);

        // Phase 10: cloud sync. Every synced table gains sync_uuid (client-
        // generated identity, mirrored as the Postgres PK), updatedAt (local
        // "last touched", unrelated to conflict resolution), and syncedAt
        // (null until first successful push). All but foods/recipes also
        // gain deletedAt (those two already carry it from v24's RB-05
        // tombstone). Mirrors `supabase/migrations/000{1,2}_sync_schema_*.sql`
        // — see `SyncColumns`/`SyncTombstone` in tables.dart.
        Future<void> tryAddColumn(
          TableInfo<Table, dynamic> table,
          GeneratedColumn column,
        ) async {
          try {
            await m.addColumn(table, column);
          } catch (_) {
            // Table/column doesn't exist on this fixture, or (MachineSettings
            // .updatedAt only) the column already existed pre-sync — same
            // swallow-and-move-on precedent as the v24 block above.
          }
        }

        final syncColumnTables = <TableInfo<Table, dynamic>>[
          gyms,
          workoutFolders,
          exerciseCatalog,
          accessories,
          bands,
          nutritionTargets,
          dietSchedules,
          carbCyclePlans,
          fastingSessions,
          bodyMeasurements,
          cycleLogs,
          cycleSettings,
          exerciseRotations,
          dailySummaries,
          externalEvents,
          microWorkouts,
          recipeIngredients,
          workoutTemplates,
          workoutSessions,
          programs,
          exerciseProgressions,
          machineSettings,
          foodEntries,
          workoutExercises,
          templateExercises,
          programWeeks,
          rotationMembers,
          setEntries,
          templateSets,
          programDays,
          programDayExercises,
          scheduledWorkouts,
          setAccessories,
          setBands,
        ];
        for (final t in syncColumnTables) {
          await tryAddColumn(t, (t as dynamic).syncUuid as GeneratedColumn);
          await tryAddColumn(t, (t as dynamic).updatedAt as GeneratedColumn);
          await tryAddColumn(t, (t as dynamic).syncedAt as GeneratedColumn);
          await tryAddColumn(t, (t as dynamic).deletedAt as GeneratedColumn);
        }
        // foods/recipes: skip deletedAt, already present since v24.
        for (final t in <TableInfo<Table, dynamic>>[foods, recipes]) {
          await tryAddColumn(t, (t as dynamic).syncUuid as GeneratedColumn);
          await tryAddColumn(t, (t as dynamic).updatedAt as GeneratedColumn);
          await tryAddColumn(t, (t as dynamic).syncedAt as GeneratedColumn);
        }

        await tryAddColumn(
          pendingSyncOps,
          pendingSyncOps.userId as GeneratedColumn,
        );
        await tryAddColumn(
          pendingSyncOps,
          pendingSyncOps.attempts as GeneratedColumn,
        );
        await tryAddColumn(
          pendingSyncOps,
          pendingSyncOps.lastError as GeneratedColumn,
        );
        await tryAddColumn(
          pendingSyncOps,
          pendingSyncOps.nextRetryAt as GeneratedColumn,
        );

        // Backfill sync_uuid for rows that predate this migration — same
        // per-row customUpdate pattern as v22's workoutSessions.sessionUuid.
        for (final tableName in syncedTableNames) {
          try {
            await backfillSyncUuids(this, tableName);
          } catch (_) {
            // Table doesn't exist on this fixture.
          }
        }

        for (final tableName in syncedTableNames) {
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_$tableName '
              'ON $tableName(sync_uuid)',
            );
          } catch (_) {
            // Table doesn't exist on this fixture.
          }
        }
        try {
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_sync_ops_entity '
            'ON pending_sync_ops(entity_type, entity_id)',
          );
        } catch (_) {
          // Pre-existing duplicate rows (shouldn't happen — queueSyncOp was
          // never called in production — but don't let a stale fixture
          // block the rest of the migration).
        }

        await installSyncTriggers(this);
      }
      if (from < 26) {
        // Assisted rep tracking (Phase 10). Three local-only tables — no
        // sync columns, no outbox trigger, no entry in syncedTableNames.
        // No backfill: the absence of a row correctly means "no consent
        // given" and "not enabled for this exercise".
        await m.createTable(repTrackingSettings);
        await m.createTable(repTrackingExercisePrefs);
        await m.createTable(repSetObservations);
      }
      if (from < 27) {
        // UI rework Phase 6: recurring fasting "notify to start" schedules.
        // Synced (SyncColumns + SyncTombstone), so it needs the same
        // sync_uuid unique index and outbox trigger every other synced table
        // gets in onCreate — mirrored here for upgrades.
        await m.createTable(fastingSchedules);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_fasting_schedules '
          'ON fasting_schedules(sync_uuid)',
        );
        // Re-runs for every synced table, but each CREATE TRIGGER/INDEX is
        // guarded IF NOT EXISTS, so this only actually installs the three
        // new triggers for fasting_schedules — same idiom as the v25 block.
        await installSyncTriggers(this);
      }
      if (from < 28 && to >= 28) {
        // UI rework Phase 8: session start times. Both columns are plain
        // nullable ints with no default and no REFERENCES clause, so these
        // are ordinary ALTER TABLE ADD COLUMNs — no legacy_alter_table
        // rebuild, and (per RB-04's sync design) no sync_table_specs.dart
        // change is needed either: SyncService derives the remote payload
        // generically from whatever local columns exist beyond the
        // registered FK/localOnly/dateTime ones.
        //
        // The `to >= 28` half of the guard matters here specifically (no
        // other block in this function checks `to`): `SchemaVerifier.
        // migrateAndValidate` fakes an intermediate target version, so a
        // v25/26/27 migration test calls this closure with `from` below 28
        // but `to` well below 28 too. Without the check, this block would
        // still fire (blocks above only ever gate on `from`) and add these
        // columns onto program_days/scheduled_workouts — tables that already
        // exist at every one of those versions — which then shows up as an
        // unexpected extra column against that older version's frozen
        // reference schema. createTable-based blocks don't have this
        // problem (IF NOT EXISTS makes an early table creation a silent
        // no-op against a schema that doesn't track columns on a table that
        // isn't compared at all until its own version), but addColumn has no
        // such guard, so it needs to actually gate on `to` here.
        //
        // Same try/catch-per-column idiom as the v24/v25 blocks above:
        // several migration tests build a fresh (current-schema) database via
        // onCreate, then rewind its stamped user_version to simulate an old
        // install, so these columns can already exist by the time this block
        // runs — addColumn (unlike createTable) has no IF NOT EXISTS guard.
        Future<void> tryAddColumn(
          TableInfo<Table, dynamic> table,
          GeneratedColumn column,
        ) async {
          try {
            await m.addColumn(table, column);
          } catch (_) {
            // Column already exists on this fixture; see comment above.
          }
        }

        await tryAddColumn(programDays, programDays.startTimeMinutes);
        await tryAddColumn(scheduledWorkouts, scheduledWorkouts.startTimeMinutes);
      }
    },
    // RB-04 Phase 3: this is the only place PRAGMA foreign_keys = ON is
    // issued. It cannot live in onCreate/onUpgrade — those run inside a
    // drift migration transaction, and SQLite silently ignores the pragma
    // when set inside a transaction (see Phase 0's discovery, and the
    // openTestDatabase() helper that has to force a query before issuing
    // it for the same reason). beforeOpen runs after the migration
    // transaction commits but before the database is handed back to
    // callers, so every enforcement-dependent read/write in the app sees
    // the pragma already on, and Phase 2's migration-time repair work
    // above always runs with enforcement off.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // The exercise catalogue is an app asset, not a schema concern. Refresh
      // it on every open so catalogue-only releases (e.g. cardio entries)
      // become visible on existing installs without a database migration.
      await ExerciseImporter.runFromAsset(this);
    },
  );
}

QueryExecutor _open() => driftDatabase(name: 'herculex');
