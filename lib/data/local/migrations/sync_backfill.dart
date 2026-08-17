import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// All local (snake_case) table names that participate in Phase 10 cloud
/// sync — mirrors `supabase/migrations/000{1,2}_sync_schema_*.sql` exactly.
/// Used by the v25 migration to backfill `sync_uuid` on existing rows and
/// by [installSyncTriggers] to wire up the outbox.
const List<String> syncedTableNames = [
  'gyms',
  'workout_folders',
  'exercise_catalog',
  'foods',
  'recipes',
  'accessories',
  'bands',
  'nutrition_targets',
  'diet_schedules',
  'carb_cycle_plans',
  'fasting_sessions',
  'body_measurements',
  'cycle_logs',
  'cycle_settings',
  'exercise_rotations',
  'daily_summaries',
  'external_events',
  'micro_workouts',
  'recipe_ingredients',
  'workout_templates',
  'workout_sessions',
  'programs',
  'exercise_progressions',
  'machine_settings',
  'food_entries',
  'workout_exercises',
  'template_exercises',
  'program_weeks',
  'rotation_members',
  'set_entries',
  'template_sets',
  'program_days',
  'program_day_exercises',
  'scheduled_workouts',
  'set_accessories',
  'set_bands',
  'fasting_schedules',
];

/// Catalogue tables whose sync trigger must only fire for `is_custom = 1`
/// rows — seeded rows never leave the device (see `0001_sync_schema_core.sql`).
const List<String> isCustomFilteredTableNames = [
  'exercise_catalog',
  'foods',
  'recipes', // no isCustom column — every recipe is user-authored, always fires
  'accessories',
  'bands',
];

/// v25 migration step: every synced table just gained a nullable `sync_uuid`
/// text column (via `tryAddColumn`); this fills it in for rows that predate
/// the migration, one `UPDATE` per row, following the exact precedent set by
/// v22's `workoutSessions.sessionUuid` backfill in `database.dart`.
///
/// Takes [GeneratedDatabase] and a raw table name (not a Drift `TableInfo`)
/// so one function serves all ~35 tables without 35 near-identical
/// hand-written loops — migration code is written against raw SQL rather
/// than the current-schema Drift accessors anyway, per `fk_repair.dart`'s
/// convention.
Future<int> backfillSyncUuids(GeneratedDatabase db, String tableName) async {
  // `rowid` must be aliased — selected bare, sqlite3's dart bindings report
  // its column name as empty and Drift's QueryRow.data drops it, so
  // row.data['rowid'] silently reads null and every WHERE rowid = ? below
  // would match nothing.
  final rows = await db
      .customSelect(
        'SELECT rowid AS row_id FROM $tableName WHERE sync_uuid IS NULL',
      )
      .get();
  const uuid = Uuid();
  for (final row in rows) {
    final rowid = row.data['row_id'];
    await db.customUpdate(
      'UPDATE $tableName SET sync_uuid = ? WHERE rowid = ?',
      variables: [Variable(uuid.v4()), Variable(rowid)],
      updates: {},
    );
  }
  return rows.length;
}
