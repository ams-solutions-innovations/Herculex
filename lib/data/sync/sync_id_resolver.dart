import 'package:drift/drift.dart';

/// Resolves between a synced table's local autoincrement `id` (used by every
/// local FK/UI code path, untouched by this phase) and its `sync_uuid` (the
/// only identity Postgres knows about). Every table's push/pull code shares
/// this helper rather than re-deriving the lookup per table.
///
/// Also resolves the catalogue "dual-column" FKs: a reference to
/// `ExerciseCatalog`/`Foods`/`Accessories`/`Bands` travels as a `sync_uuid`
/// when it points at a *custom* row (pushed to Postgres like any other
/// synced row) or as a stable natural key (slug / catalogueId / kind /
/// color+tension) when it points at a *seeded* row — seeded rows are never
/// pushed, but exist identically on every device from the same bundled
/// assets, so the natural key resolves locally on the receiving side.
///
/// Written against raw `customSelect`/`customUpdate` rather than typed Drift
/// table accessors, matching the migration-code convention elsewhere in this
/// package (`fk_repair.dart`, `nutrition_snapshot_backfill.dart`) — sync code
/// runs against whatever schema shape is live, and operating on raw SQL row
/// maps (already snake_case) is what lets `SyncService` stay generic across
/// ~35 tables instead of hand-writing per-table column mapping.
class SyncIdResolver {
  SyncIdResolver(this._db);

  final GeneratedDatabase _db;

  /// Local int `id` -> `sync_uuid` for a plain synced-table FK (e.g.
  /// `set_entries.workout_exercise_id` -> `workout_exercises.sync_uuid`).
  Future<String?> localIdToSyncUuid(String table, int localId) async {
    final row = await _db
        .customSelect(
          'SELECT sync_uuid FROM $table WHERE id = ?',
          variables: [Variable(localId)],
        )
        .getSingleOrNull();
    return row?.data['sync_uuid'] as String?;
  }

  /// `sync_uuid` -> local int `id`, upserting nothing — the parent row must
  /// already exist locally (pull runs parents before children, per
  /// `SyncTableSpecs.pullOrder`).
  Future<int?> syncUuidToLocalId(String table, String syncUuid) async {
    final row = await _db
        .customSelect(
          'SELECT id FROM $table WHERE sync_uuid = ?',
          variables: [Variable(syncUuid)],
        )
        .getSingleOrNull();
    return row?.data['id'] as int?;
  }

  /// Resolves a catalogue FK (single natural-key column, e.g. `slug` for
  /// exercises, `catalogue_id` for foods, `kind` for accessories) to its
  /// push-time remote representation: `(uuidColumnValue, naturalKeyValue)`
  /// with exactly one non-null, per the schema's `check` constraints.
  Future<(String? uuid, String? naturalKey)> resolveCatalogueRefForPush({
    required String localTable,
    required int localId,
    required String naturalKeyColumn,
    required String isCustomColumn,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT sync_uuid, $naturalKeyColumn AS natural_key, '
          '$isCustomColumn AS is_custom FROM $localTable WHERE id = ?',
          variables: [Variable(localId)],
        )
        .getSingleOrNull();
    if (row == null) return (null, null);
    final isCustom = (row.data['is_custom'] as int? ?? 0) != 0;
    if (isCustom) {
      return (row.data['sync_uuid'] as String?, null);
    }
    return (null, row.data['natural_key'] as String?);
  }

  /// Reverse of [resolveCatalogueRefForPush]: given whichever of the pulled
  /// row's (uuid, naturalKey) pair is populated, finds the local int id.
  Future<int?> resolveCatalogueRefForPull({
    required String localTable,
    required String naturalKeyColumn,
    String? uuid,
    String? naturalKey,
  }) async {
    if (uuid != null) return syncUuidToLocalId(localTable, uuid);
    if (naturalKey != null) {
      final row = await _db
          .customSelect(
            'SELECT id FROM $localTable WHERE $naturalKeyColumn = ?',
            variables: [Variable(naturalKey)],
          )
          .getSingleOrNull();
      return row?.data['id'] as int?;
    }
    return null;
  }

  /// Bands are the one catalogue table with no single natural-key column —
  /// seeded rows resolve by the `(color, tensionKg)` pair instead.
  Future<(String? uuid, String? color, double? tensionKg)>
  resolveBandRefForPush(int localId) async {
    final row = await _db
        .customSelect(
          'SELECT sync_uuid, color, tension_kg, is_custom FROM bands WHERE id = ?',
          variables: [Variable(localId)],
        )
        .getSingleOrNull();
    if (row == null) return (null, null, null);
    final isCustom = (row.data['is_custom'] as int? ?? 0) != 0;
    if (isCustom) return (row.data['sync_uuid'] as String?, null, null);
    return (
      null,
      row.data['color'] as String?,
      row.data['tension_kg'] as double?,
    );
  }

  Future<int?> resolveBandRefForPull({
    String? uuid,
    String? color,
    double? tensionKg,
  }) async {
    if (uuid != null) return syncUuidToLocalId('bands', uuid);
    if (color != null && tensionKg != null) {
      final row = await _db
          .customSelect(
            'SELECT id FROM bands WHERE color = ? AND tension_kg = ?',
            variables: [Variable(color), Variable(tensionKg)],
          )
          .getSingleOrNull();
      return row?.data['id'] as int?;
    }
    return null;
  }
}
