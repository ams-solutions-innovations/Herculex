import 'package:drift/drift.dart';

/// Per-edge counts produced by [repairForeignKeyViolations], for logging and
/// for tests to assert on.
class FkRepairReport {
  const FkRepairReport({
    required this.nulled,
    required this.deleted,
    required this.residualViolations,
  });

  /// `SET NULL` edges, keyed by `'table.column'`, value = rows updated.
  final Map<String, int> nulled;

  /// Delete-orphan edges, keyed by table name, value = rows deleted.
  final Map<String, int> deleted;

  /// Rows still reported by `PRAGMA foreign_key_check` after repair. Should
  /// be 0; non-zero is logged, not thrown (see [repairForeignKeyViolations]).
  final int residualViolations;
}

/// RB-04 Phase 2: brings every existing device to zero FK violations before
/// enforcement (`PRAGMA foreign_keys = ON`) lands in Phase 3.
///
/// Takes [GeneratedDatabase] rather than `AppDatabase` so it can run from
/// both a migration and a test. Written against raw `customStatement` /
/// `customSelect` / `customUpdate` only — migration code must stay frozen
/// against the schema version it shipped with (drift table accessors track
/// the *current* schema, not the historical one), per
/// `docs/v2/02-SCHEMA-AND-MIGRATION.md`.
///
/// Runs with `PRAGMA foreign_keys` still off (migrations always do — see
/// `database.dart`'s `beforeOpen` comment), so every statement here is a
/// plain, unenforced `UPDATE`/`DELETE`.
Future<FkRepairReport> repairForeignKeyViolations(GeneratedDatabase db) async {
  final nulled = <String, int>{};
  final deleted = <String, int>{};

  // Tables referenced by these statements may not exist yet on a database
  // mid-upgrade from a very old, hand-rolled test fixture that only stamps
  // down the handful of tables its own migration step touches (see
  // test/schema_v21_test.dart) — on a real device every table here was
  // created by an earlier `onUpgrade` step long before v23. Swallow "no such
  // table" the same way the v17 report-only sweep this supersedes did.
  Future<void> nullEdge(String key, String sql) async {
    try {
      nulled[key] = await db.customUpdate(sql);
    } catch (_) {
      nulled[key] = 0;
    }
  }

  Future<void> deleteOrphans(String table, String sql) async {
    try {
      deleted[table] = await db.customUpdate(sql);
    } catch (_) {
      deleted[table] = 0;
    }
  }

  // ── Pass 1: NULL the 8 SET NULL edges first. Byte-for-byte what the
  // constraint would have done on delete, zero information loss. One of
  // these (scheduled_workouts.completed_session_id) also has a sibling
  // column that would be left semantically wrong by a bare NULL — a
  // schedule row claiming status='done' with no completed session — so
  // that repair resets status alongside the NULL in the same statement.
  await nullEdge('machine_settings.gym_id', '''
    UPDATE machine_settings SET gym_id = NULL
    WHERE gym_id IS NOT NULL AND gym_id NOT IN (SELECT id FROM gyms)
  ''');
  await nullEdge('program_day_exercises.rotation_id', '''
    UPDATE program_day_exercises SET rotation_id = NULL
    WHERE rotation_id IS NOT NULL
      AND rotation_id NOT IN (SELECT id FROM exercise_rotations)
  ''');
  await nullEdge('program_days.template_id', '''
    UPDATE program_days SET template_id = NULL
    WHERE template_id IS NOT NULL
      AND template_id NOT IN (SELECT id FROM workout_templates)
  ''');
  await nullEdge('scheduled_workouts.template_id_override', '''
    UPDATE scheduled_workouts SET template_id_override = NULL
    WHERE template_id_override IS NOT NULL
      AND template_id_override NOT IN (SELECT id FROM workout_templates)
  ''');
  await nullEdge('scheduled_workouts.completed_session_id', '''
    UPDATE scheduled_workouts
    SET completed_session_id = NULL,
        status = CASE WHEN status = 'done' THEN 'planned' ELSE status END
    WHERE completed_session_id IS NOT NULL
      AND completed_session_id NOT IN (SELECT id FROM workout_sessions)
  ''');
  await nullEdge('workout_sessions.micro_workout_id', '''
    UPDATE workout_sessions SET micro_workout_id = NULL
    WHERE micro_workout_id IS NOT NULL
      AND micro_workout_id NOT IN (SELECT id FROM micro_workouts)
  ''');
  await nullEdge('workout_sessions.gym_id', '''
    UPDATE workout_sessions SET gym_id = NULL
    WHERE gym_id IS NOT NULL AND gym_id NOT IN (SELECT id FROM gyms)
  ''');
  await nullEdge('workout_templates.folder_id', '''
    UPDATE workout_templates SET folder_id = NULL
    WHERE folder_id IS NOT NULL
      AND folder_id NOT IN (SELECT id FROM workout_folders)
  ''');

  // ── Pass 2: delete orphans, deepest-first, so deleting a table never
  // manufactures a new orphan in a table already processed.
  await deleteOrphans('set_accessories', '''
    DELETE FROM set_accessories
    WHERE accessory_id NOT IN (SELECT id FROM accessories)
       OR set_entry_id NOT IN (SELECT id FROM set_entries)
  ''');
  await deleteOrphans('set_bands', '''
    DELETE FROM set_bands
    WHERE band_id NOT IN (SELECT id FROM bands)
       OR set_entry_id NOT IN (SELECT id FROM set_entries)
  ''');
  await deleteOrphans('set_entries', '''
    DELETE FROM set_entries
    WHERE workout_exercise_id NOT IN (SELECT id FROM workout_exercises)
  ''');
  await deleteOrphans('workout_exercises', '''
    DELETE FROM workout_exercises
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
       OR session_id NOT IN (SELECT id FROM workout_sessions)
  ''');
  await deleteOrphans('template_sets', '''
    DELETE FROM template_sets
    WHERE template_exercise_id NOT IN (SELECT id FROM template_exercises)
  ''');
  await deleteOrphans('template_exercises', '''
    DELETE FROM template_exercises
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
       OR template_id NOT IN (SELECT id FROM workout_templates)
  ''');
  await deleteOrphans('program_day_exercises', '''
    DELETE FROM program_day_exercises
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
       OR program_day_id NOT IN (SELECT id FROM program_days)
  ''');
  await deleteOrphans('program_days', '''
    DELETE FROM program_days
    WHERE program_week_id NOT IN (SELECT id FROM program_weeks)
  ''');
  await deleteOrphans('program_weeks', '''
    DELETE FROM program_weeks
    WHERE program_id NOT IN (SELECT id FROM programs)
  ''');
  await deleteOrphans('scheduled_workouts', '''
    DELETE FROM scheduled_workouts
    WHERE program_day_id NOT IN (SELECT id FROM program_days)
       OR (program_id IS NOT NULL AND program_id NOT IN (SELECT id FROM programs))
  ''');
  await deleteOrphans('recipe_ingredients', '''
    DELETE FROM recipe_ingredients
    WHERE recipe_id NOT IN (SELECT id FROM recipes)
       OR food_id NOT IN (SELECT id FROM foods)
  ''');
  await deleteOrphans('food_micros', '''
    DELETE FROM food_micros
    WHERE food_id NOT IN (SELECT id FROM foods)
  ''');
  await deleteOrphans('food_entries', '''
    DELETE FROM food_entries
    WHERE (recipe_id IS NOT NULL AND recipe_id NOT IN (SELECT id FROM recipes))
       OR (food_id IS NOT NULL AND food_id NOT IN (SELECT id FROM foods))
  ''');
  await deleteOrphans('rotation_members', '''
    DELETE FROM rotation_members
    WHERE rotation_id NOT IN (SELECT id FROM exercise_rotations)
       OR exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');
  await deleteOrphans('micro_workouts', '''
    DELETE FROM micro_workouts
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');
  await deleteOrphans('exercise_muscles', '''
    DELETE FROM exercise_muscles
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');
  await deleteOrphans('exercise_aliases', '''
    DELETE FROM exercise_aliases
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');
  await deleteOrphans('exercise_progressions', '''
    DELETE FROM exercise_progressions
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');
  await deleteOrphans('machine_settings', '''
    DELETE FROM machine_settings
    WHERE exercise_id NOT IN (SELECT id FROM exercise_catalog)
  ''');

  // ── Post-condition: re-run the same census used to open this repair.
  // Non-empty residue is logged, never thrown — throwing here would roll
  // back the whole migration transaction and boot-loop the device. A
  // leftover violation only bites on a future UPDATE of that row, which is
  // strictly better than bricking the upgrade.
  final residual = await db.customSelect('PRAGMA foreign_key_check').get();

  return FkRepairReport(
    nulled: nulled,
    deleted: deleted,
    residualViolations: residual.length,
  );
}
