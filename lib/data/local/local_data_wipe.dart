import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Variable;
import 'package:herculex/services/platform/widget_sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Erases every trace of the signed-in person from this device.
///
/// Used by account deletion, local "Clear All Data", and account switching on a
/// shared device. Signing out alone leaves the local database intact on purpose
/// (Herculex is local-first and works fully offline), while deleting an
/// account, clearing all local data, or signing in as a *different* user must
/// leave nothing behind from the previous user.
///
/// What deliberately survives is the *bundled catalogue* and seeded reference
/// rules: the ~45k seeded foods, seeded exercises, accessories, bands, Hercul
/// coaching rules, and fasting stage definitions. Those are shipped assets,
/// identical on every install, and contain nothing about the user —
/// re-importing them would cost a multi-second migration on next launch to
/// achieve nothing. Their import marker ([AppDatabase.foodCatalogueMeta]) is
/// preserved for the same reason.
///
/// Everything the user authored *inside* the catalogue tables is a custom row
/// (`is_custom = 1`) and does go, taking its children with it through the
/// `on delete cascade` already declared on `exercise_muscles`,
/// `exercise_aliases` and `food_micros`.
Future<void> wipeAllLocalUserData(
  GeneratedDatabase db, {
  Directory? documentsDirectory,
}) async {
  final docs = await _resolveDocsDir(documentsDirectory);
  await _deleteReferencedPhotoFiles(db, docs);
  await _deleteSandboxSubdirectory(docs, physiquePhotoFolderName);
  await _deleteSandboxSubdirectory(docs, progressPhotoFolderName);
  await _deleteSandboxSubdirectory(docs, workoutPhotoFolderName);
  await _deleteSandboxSubdirectory(docs, labsFolderName);

  await db.transaction(() async {
    // Ordinary `DELETE`s in an order that does not follow the FK graph, so
    // enforcement is deferred to commit time. `PRAGMA foreign_keys` cannot be
    // changed inside a transaction (SQLite silently ignores it); this is the
    // documented in-transaction equivalent, and it means the table list below
    // can stay grouped by meaning rather than sorted by dependency.
    await db.customStatement('PRAGMA defer_foreign_keys = ON');

    for (final table in catalogueTables) {
      await db.customUpdate('DELETE FROM $table WHERE is_custom = 1');
    }
    for (final table in fullyClearedTables) {
      await db.customUpdate('DELETE FROM $table');
    }
    for (final table in rawWatchTables) {
      final exists = await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable.withString(table)],
          )
          .getSingleOrNull();
      if (exists != null) {
        await db.customUpdate('DELETE FROM $table');
      }
    }

    // Last, and in this order. Every delete above fires the outbox triggers,
    // so clearing the outbox first would just refill it; and `sync_cursors`
    // holds the local-database owner key that decides whether the next
    // sign-in is treated as an account switch, which it now is.
    for (final table in syncMetadataTables) {
      await db.customUpdate('DELETE FROM $table');
    }
  });

  await WidgetSyncService().clearAll();
}

Future<Directory?> _resolveDocsDir(Directory? override) async {
  if (override != null) return override;
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return null;
  }
}

/// Progress photos and workout finish photos store paths on disk (either
/// sandbox-relative under `<documents>/progress_photos/` and
/// `<documents>/workout_photos/`, or legacy absolute paths). Deleting only the
/// SQLite rows would orphan JPEGs on disk.
Future<void> _deleteReferencedPhotoFiles(
  GeneratedDatabase db,
  Directory? docs,
) async {
  final paths = <String>{};
  try {
    final progressRows = await db
        .customSelect('SELECT file_path FROM progress_photos')
        .get();
    for (final row in progressRows) {
      final path = row.readNullable<String>('file_path')?.trim();
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }
  } catch (_) {}

  try {
    final sessionRows = await db
        .customSelect(
          'SELECT photo_path FROM workout_sessions WHERE photo_path IS NOT NULL',
        )
        .get();
    for (final row in sessionRows) {
      final photoPath = row.readNullable<String>('photo_path')?.trim();
      if (photoPath != null && photoPath.isNotEmpty) {
        paths.add(photoPath);
      }
    }
  } catch (_) {}

  for (final rawPath in paths) {
    try {
      final File file;
      if (p.isAbsolute(rawPath) || docs == null) {
        file = File(rawPath);
      } else {
        file = File(p.join(docs.path, rawPath));
      }
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // A missing or unreadable file must not abort the wipe — the row is
      // going either way, and a leftover file the OS would not let us touch
      // is not a reason to leave the database populated.
    }
  }
}

/// Folder under the documents directory holding private physique photos.
/// Must equal `PhysiquePhotoStore.rootFolderName` (enforced by a test, so this
/// file does not have to import a feature).
const physiquePhotoFolderName = 'physique';

/// Folder under the documents directory holding sandboxed progress photos.
const progressPhotoFolderName = 'progress_photos';

/// Folder under the documents directory holding sandboxed workout photos.
const workoutPhotoFolderName = 'workout_photos';

/// Folder under the documents directory holding exported PDF reports.
const labsFolderName = 'labs';

Future<void> _deleteSandboxSubdirectory(
  Directory? docs,
  String folderName,
) async {
  if (docs == null) return;
  try {
    final dir = Directory(p.join(docs.path, folderName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {
    // Private storage can be unavailable in headless tests or locked by OS.
  }
}

/// Seeded + custom rows share these tables; only the custom ones (`is_custom = 1`)
/// belong to the user.
const catalogueTables = ['exercise_catalog', 'foods', 'accessories', 'bands'];

/// Every Drift table that holds user data end to end.
const fullyClearedTables = [
  'training_coaching_overrides',
  'training_coaching_proposals',
  'workout_behavior_snapshots',
  'exercise_history_transfers',
  'workout_reports',
  'workout_report_events',
  'workout_report_plans',
  // Training
  'workout_sessions',
  'workout_exercises',
  'set_entries',
  'set_accessories',
  'set_bands',
  'workout_circuits',
  'circuit_exercises',
  'workout_folders',
  'workout_templates',
  'template_exercises',
  'template_sets',
  'programs',
  'program_weeks',
  'program_days',
  'program_exercise_slots',
  'program_slot_pool_members',
  'program_slot_explanations',
  'rotation_assignments',
  'prescription_templates',
  'physique_programming_profiles',
  'exercise_preferences',
  'program_day_exercises',
  'scheduled_workouts',
  'adaptation_proposals',
  'adaptation_overrides',
  'exercise_rotations',
  'rotation_members',
  'exercise_progressions',
  'micro_workouts',
  'machine_settings',
  'gyms',
  'gym_equipment',
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
  // Body, health, joint pain and cycle — GDPR Article 9 rows
  'body_measurements',
  'progress_photos',
  'health_samples',
  'cycle_logs',
  'cycle_settings',
  'joint_pain_logs',
  'external_events',
  // Local-only feature & coaching state
  'buddy_sessions_local',
  'buddy_choreography_slots',
  'achievements',
  'hercul_message_log',
  // Physique goals, assessments, roadmaps and photo metadata (Article 9).
  'physique_goals',
  'physique_assessments',
  'physique_roadmap_phases',
  'physique_photos',
  // Synced user tables
  'tdee_estimates',
  'herculex_ai_program_briefs',
  // Weekly reports hold aggregated health data (GDPR Art. 9).
  'weekly_reports',
  // The synced mirror of the profile and settings (the preferences themselves
  // are cleared separately, with SharedPreferences).
  'user_preferences',
];

/// Sync bookkeeping tables cleared at the very end of the wipe transaction
/// after all outbox triggers have fired.
const syncMetadataTables = ['pending_sync_ops', 'sync_cursors'];

/// Drift tables that hold shipped static assets or cascade-deleted catalogue
/// metadata (`exercise_muscles`, `exercise_aliases`, `food_micros` lose their
/// custom rows automatically via `ON DELETE CASCADE` on [catalogueTables]).
const preservedReferenceTables = [
  'exercise_muscles',
  'exercise_aliases',
  'food_micros',
  'food_catalogue_meta',
  'hercul_rules',
  'fasting_stages',
];

/// Raw SQLite tables created outside `@DriftDatabase` by `WatchCommandInbox`.
const rawWatchTables = [
  'processed_watch_commands',
  'apple_watch_sessions',
  'watch_health_exports',
];
