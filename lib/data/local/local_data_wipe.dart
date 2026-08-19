import 'dart:io';

import 'database.dart';

/// Erases every trace of the signed-in person from this device.
///
/// Used by account deletion, which is not the same operation as sign-out:
/// signing out leaves the local database intact on purpose (Herculex is
/// local-first and works fully offline), while deleting the account has to
/// leave nothing behind — the cloud side is already gone by the time this
/// runs, and a device still holding the whole training history would make
/// "delete my account" a lie.
///
/// What deliberately survives is the *bundled catalogue*: the ~45k seeded
/// foods and the seeded exercise rows. Those are shipped assets, identical on
/// every install, and contain nothing about the user — re-importing them would
/// cost a multi-second migration on next launch to achieve nothing. Their
/// import marker ([AppDatabase.foodCatalogueMeta]) is preserved for the same
/// reason.
///
/// Everything the user authored *inside* those tables is a custom row
/// (`is_custom = 1`) and does go, taking its children with it through the
/// `on delete cascade` already declared on `exercise_muscles`,
/// `exercise_aliases` and `food_micros`.
Future<void> wipeAllLocalUserData(AppDatabase db) async {
  await _deleteProgressPhotoFiles(db);

  await db.transaction(() async {
    // Ordinary `DELETE`s in an order that does not follow the FK graph, so
    // enforcement is deferred to commit time. `PRAGMA foreign_keys` cannot be
    // changed inside a transaction (SQLite silently ignores it); this is the
    // documented in-transaction equivalent, and it means the table list below
    // can stay grouped by meaning rather than sorted by dependency.
    await db.customStatement('PRAGMA defer_foreign_keys = ON');

    for (final table in _catalogueTables) {
      await db.customUpdate('DELETE FROM $table WHERE is_custom = 1');
    }
    for (final table in _fullyClearedTables) {
      await db.customUpdate('DELETE FROM $table');
    }

    // Last, and in this order. Every delete above fires the outbox triggers,
    // so clearing the outbox first would just refill it; and `sync_cursors`
    // holds the local-database owner key that decides whether the next
    // sign-in is treated as an account switch, which it now is.
    await db.customUpdate('DELETE FROM pending_sync_ops');
    await db.customUpdate('DELETE FROM sync_cursors');
  });
}

/// Progress photos are the one kind of user content that lives outside SQLite
/// — the row stores a path into the app documents directory. Deleting only the
/// rows would orphan the JPEGs on disk, which is exactly the file-type a
/// deletion request is most sensitive about.
Future<void> _deleteProgressPhotoFiles(AppDatabase db) async {
  final rows = await db.select(db.progressPhotos).get();
  for (final row in rows) {
    try {
      final file = File(row.filePath);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A missing or unreadable file must not abort the wipe — the row is
      // going either way, and a leftover file the OS would not let us touch
      // is not a reason to leave the database populated.
    }
  }
}

/// Seeded + custom rows share these tables; only the custom ones are the
/// user's. Mirrors `isCustomFilteredTableNames` in
/// `migrations/sync_backfill.dart`, minus `recipes` — every recipe is
/// user-authored and it has no `is_custom` column, so it is cleared whole
/// below.
const _catalogueTables = ['exercise_catalog', 'foods', 'accessories', 'bands'];

/// Everything that is user data end to end.
///
/// `exercise_muscles`, `exercise_aliases` and `food_micros` are absent on
/// purpose: they hold seeded catalogue metadata as well as custom-row
/// metadata, and the custom half is already removed by cascade. `pending_sync_ops`
/// and `sync_cursors` are absent because they are cleared last, after the
/// deletes that write to them. `food_catalogue_meta` is absent because the
/// catalogue it marks is being kept.
const _fullyClearedTables = [
  // Training
  'workout_sessions',
  'workout_exercises',
  'set_entries',
  'set_accessories',
  'set_bands',
  'workout_folders',
  'workout_templates',
  'template_exercises',
  'template_sets',
  'programs',
  'program_weeks',
  'program_days',
  'program_day_exercises',
  'scheduled_workouts',
  'exercise_rotations',
  'rotation_members',
  'exercise_progressions',
  'micro_workouts',
  'machine_settings',
  'gyms',
  // Nutrition
  'recipes',
  'recipe_ingredients',
  'food_entries',
  'nutrition_targets',
  'diet_schedules',
  'carb_cycle_plans',
  'fasting_sessions',
  'fasting_schedules',
  'daily_summaries',
  // Body, health and cycle — the GDPR Article 9 rows
  'body_measurements',
  'progress_photos',
  'health_samples',
  'cycle_logs',
  'cycle_settings',
  'external_events',
  // Local-only feature state
  'rep_tracking_settings',
  'rep_tracking_exercise_prefs',
  'rep_set_observations',
  'buddy_sessions_local',
  'buddy_choreography_slots',
];
