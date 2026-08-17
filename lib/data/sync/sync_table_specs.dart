/// The ~35-table sync registry — kept separate from `sync_service.dart` so
/// the orchestrator stays readable. Order matters: [syncTableOrder] is
/// parent-before-child, matching `supabase/migrations/000{1,2}_*.sql` and
/// `sync_backfill.dart`'s `syncedTableNames` — both push (Postgres FK
/// constraints require the parent row to exist first) and pull (resolving a
/// remote FK back to a local int id requires the local parent row to already
/// exist) walk tables in this order.
library;

/// A plain FK to another synced table: local int `<localColumn>` resolves to
/// that table's `sync_uuid`, transmitted under `remoteColumn` (almost always
/// the same name as `localColumn`).
class SimpleFk {
  const SimpleFk({
    required this.localColumn,
    required this.parentTable,
    String? remoteColumn,
  }) : remoteColumn = remoteColumn ?? localColumn;

  final String localColumn;
  final String parentTable;
  final String remoteColumn;
}

/// A FK into a catalogue table (`exercise_catalog`, `foods`, `accessories`)
/// that may point at either a custom row (travels as a `sync_uuid`) or a
/// seeded row (travels as a stable natural key — same value on every device
/// since seeded rows come from the same bundled assets). See
/// `SyncIdResolver.resolveCatalogueRefForPush`.
class CatalogueFk {
  const CatalogueFk({
    required this.localColumn,
    required this.parentTable,
    required this.naturalKeyColumn,
    required this.isCustomColumn,
    required this.remoteUuidColumn,
    required this.remoteNaturalKeyColumn,
  });

  final String localColumn;
  final String parentTable;
  final String naturalKeyColumn;
  final String isCustomColumn;
  final String remoteUuidColumn;
  final String remoteNaturalKeyColumn;
}

/// Bands have no single natural-key column for seeded rows — resolved by
/// `(color, tensionKg)` instead. One-off shape, only used by `set_bands`.
class BandFk {
  const BandFk({required this.localColumn});
  final String localColumn;
}

typedef SyncFkField = Object; // SimpleFk | CatalogueFk | BandFk

class SyncTableSpec {
  const SyncTableSpec(
    this.table, {
    this.fkFields = const [],
    this.localOnlyColumns = const [],
    this.columnRenames = const {},
    this.dateTimeColumns = const [],
  });
  final String table;
  final List<SyncFkField> fkFields;

  /// Non-meta `DateTimeColumn`s (Drift stores these as unix-epoch-seconds
  /// integers locally; Postgres wants `timestamptz` ISO 8601 strings) that
  /// `SyncService` must convert on push/pull. `deleted_at` is always
  /// converted too — every synced table has it, so it isn't repeated here.
  final List<String> dateTimeColumns;

  /// Local columns with no remote counterpart, beyond the universal
  /// `id`/`sync_uuid`/`updated_at`/`synced_at` every table drops — e.g.
  /// `slug`/`catalogue_id` on catalogue tables, which are the natural keys
  /// of *seeded* rows and are therefore always null on the custom rows that
  /// are the only ones ever pushed.
  ///
  /// Note `is_custom` is deliberately **not** in this list, despite being
  /// constantly true remotely for the same reason. It has to cross because
  /// the receiving side's local default is `false`, which would turn every
  /// pulled custom row into a seeded one — see
  /// `supabase/migrations/0007_catalogue_is_custom.sql` for what that breaks.
  final List<String> localOnlyColumns;

  /// Local column name -> remote column name, applied before the universal
  /// drop list. Only `machine_settings.updated_at` needs this today — its
  /// local column predates Phase 10 and means "last recalled", not the sync
  /// clock, so it travels as `recalled_at` instead of being silently
  /// stripped by the universal `updated_at` drop.
  final Map<String, String> columnRenames;
}

const _exerciseCatalogFk = (
  naturalKeyColumn: 'slug',
  isCustomColumn: 'is_custom',
  remoteUuidColumn: 'exercise_catalog_id',
  remoteNaturalKeyColumn: 'exercise_slug',
);

CatalogueFk _exerciseFk(String localColumn) => CatalogueFk(
  localColumn: localColumn,
  parentTable: 'exercise_catalog',
  naturalKeyColumn: _exerciseCatalogFk.naturalKeyColumn,
  isCustomColumn: _exerciseCatalogFk.isCustomColumn,
  remoteUuidColumn: _exerciseCatalogFk.remoteUuidColumn,
  remoteNaturalKeyColumn: _exerciseCatalogFk.remoteNaturalKeyColumn,
);

/// Parent-before-child. See the module doc comment.
final List<SyncTableSpec> syncTableSpecs = [
  // ── Level 0: no synced-table dependency ──────────────────────────────
  const SyncTableSpec('gyms', dateTimeColumns: ['created_at']),
  const SyncTableSpec('workout_folders', dateTimeColumns: ['created_at']),
  const SyncTableSpec(
    'exercise_catalog',
    localOnlyColumns: ['slug'],
  ),
  const SyncTableSpec(
    'foods',
    localOnlyColumns: ['catalogue_id'],
    dateTimeColumns: ['created_at'],
  ),
  const SyncTableSpec('recipes', dateTimeColumns: ['created_at']),
  // `kind` and `color`/`tension_kg` are the seeded natural keys for
  // accessories and bands, but unlike `slug`/`catalogue_id` they are real
  // data columns that custom rows populate too, so they cross normally.
  const SyncTableSpec('accessories'),
  const SyncTableSpec('bands'),
  const SyncTableSpec('nutrition_targets'),
  const SyncTableSpec('diet_schedules'),
  const SyncTableSpec('carb_cycle_plans'),
  const SyncTableSpec(
    'fasting_sessions',
    dateTimeColumns: ['started_at', 'ended_at'],
  ),
  const SyncTableSpec('fasting_schedules'),
  const SyncTableSpec('body_measurements'),
  const SyncTableSpec('cycle_logs'),
  const SyncTableSpec(
    'cycle_settings',
    dateTimeColumns: ['last_period_start'],
  ),
  const SyncTableSpec('exercise_rotations'),
  const SyncTableSpec('daily_summaries'),
  const SyncTableSpec('external_events'),
  SyncTableSpec(
    'micro_workouts',
    fkFields: [_exerciseFk('exercise_id')],
    dateTimeColumns: const ['created_at'],
  ),

  // ── Level 1 ───────────────────────────────────────────────────────────
  SyncTableSpec(
    'recipe_ingredients',
    fkFields: [
      const SimpleFk(localColumn: 'recipe_id', parentTable: 'recipes'),
      CatalogueFk(
        localColumn: 'food_id',
        parentTable: 'foods',
        naturalKeyColumn: 'catalogue_id',
        isCustomColumn: 'is_custom',
        remoteUuidColumn: 'food_catalogue_id',
        remoteNaturalKeyColumn: 'food_catalogue_ref',
      ),
    ],
  ),
  const SyncTableSpec(
    'workout_templates',
    fkFields: [
      SimpleFk(localColumn: 'folder_id', parentTable: 'workout_folders'),
    ],
    dateTimeColumns: ['created_at', 'last_used_at'],
  ),
  const SyncTableSpec(
    'workout_sessions',
    fkFields: [
      SimpleFk(localColumn: 'gym_id', parentTable: 'gyms'),
      SimpleFk(
        localColumn: 'micro_workout_id',
        parentTable: 'micro_workouts',
      ),
    ],
    // Phone<->watch wire-protocol identity (v22) — unrelated to cloud sync.
    localOnlyColumns: ['session_uuid'],
    dateTimeColumns: ['started_at', 'ended_at'],
  ),
  const SyncTableSpec('programs'),
  SyncTableSpec(
    'exercise_progressions',
    fkFields: [_exerciseFk('exercise_id')],
  ),
  SyncTableSpec(
    'machine_settings',
    fkFields: [
      _exerciseFk('exercise_id'),
      const SimpleFk(localColumn: 'gym_id', parentTable: 'gyms'),
    ],
    columnRenames: const {'updated_at': 'recalled_at'},
    dateTimeColumns: const ['recalled_at'],
  ),
  SyncTableSpec(
    'food_entries',
    fkFields: [
      CatalogueFk(
        localColumn: 'food_id',
        parentTable: 'foods',
        naturalKeyColumn: 'catalogue_id',
        isCustomColumn: 'is_custom',
        remoteUuidColumn: 'food_catalogue_id',
        remoteNaturalKeyColumn: 'food_catalogue_ref',
      ),
      const SimpleFk(localColumn: 'recipe_id', parentTable: 'recipes'),
    ],
    dateTimeColumns: const ['logged_at'],
  ),

  // ── Level 2 ───────────────────────────────────────────────────────────
  SyncTableSpec(
    'workout_exercises',
    fkFields: [
      const SimpleFk(localColumn: 'session_id', parentTable: 'workout_sessions'),
      _exerciseFk('exercise_id'),
    ],
  ),
  SyncTableSpec(
    'template_exercises',
    fkFields: [
      const SimpleFk(localColumn: 'template_id', parentTable: 'workout_templates'),
      _exerciseFk('exercise_id'),
    ],
  ),
  const SyncTableSpec(
    'program_weeks',
    fkFields: [SimpleFk(localColumn: 'program_id', parentTable: 'programs')],
  ),
  SyncTableSpec(
    'rotation_members',
    fkFields: [
      const SimpleFk(
        localColumn: 'rotation_id',
        parentTable: 'exercise_rotations',
      ),
      _exerciseFk('exercise_id'),
    ],
  ),

  // ── Level 3 ───────────────────────────────────────────────────────────
  const SyncTableSpec(
    'set_entries',
    fkFields: [
      SimpleFk(
        localColumn: 'workout_exercise_id',
        parentTable: 'workout_exercises',
      ),
    ],
    dateTimeColumns: ['completed_at'],
  ),
  const SyncTableSpec(
    'template_sets',
    fkFields: [
      SimpleFk(
        localColumn: 'template_exercise_id',
        parentTable: 'template_exercises',
      ),
    ],
  ),
  const SyncTableSpec(
    'program_days',
    fkFields: [
      SimpleFk(localColumn: 'program_week_id', parentTable: 'program_weeks'),
      SimpleFk(localColumn: 'template_id', parentTable: 'workout_templates'),
    ],
  ),

  // ── Level 4 ───────────────────────────────────────────────────────────
  SyncTableSpec(
    'program_day_exercises',
    fkFields: [
      const SimpleFk(localColumn: 'program_day_id', parentTable: 'program_days'),
      _exerciseFk('exercise_id'),
      const SimpleFk(
        localColumn: 'rotation_id',
        parentTable: 'exercise_rotations',
      ),
    ],
  ),
  const SyncTableSpec(
    'scheduled_workouts',
    fkFields: [
      SimpleFk(localColumn: 'program_day_id', parentTable: 'program_days'),
      SimpleFk(
        localColumn: 'completed_session_id',
        parentTable: 'workout_sessions',
      ),
      SimpleFk(localColumn: 'program_id', parentTable: 'programs'),
      SimpleFk(
        localColumn: 'template_id_override',
        parentTable: 'workout_templates',
        remoteColumn: 'template_id_override',
      ),
    ],
  ),

  // ── Level 5 ───────────────────────────────────────────────────────────
  const SyncTableSpec(
    'set_accessories',
    fkFields: [
      SimpleFk(localColumn: 'set_entry_id', parentTable: 'set_entries'),
      CatalogueFk(
        localColumn: 'accessory_id',
        parentTable: 'accessories',
        naturalKeyColumn: 'kind',
        isCustomColumn: 'is_custom',
        remoteUuidColumn: 'accessory_id',
        remoteNaturalKeyColumn: 'accessory_kind',
      ),
    ],
  ),
  const SyncTableSpec(
    'set_bands',
    fkFields: [
      SimpleFk(localColumn: 'set_entry_id', parentTable: 'set_entries'),
      BandFk(localColumn: 'band_id'),
    ],
  ),
];

/// Table names in dependency order — used directly by [syncedTableNames] in
/// `sync_backfill.dart` too (kept as a separate source list there to avoid a
/// migrations-package -> sync-package import in the other direction).
List<String> get syncTableOrder =>
    syncTableSpecs.map((s) => s.table).toList(growable: false);

final Map<String, SyncTableSpec> syncTableSpecsByName = {
  for (final spec in syncTableSpecs) spec.table: spec,
};
