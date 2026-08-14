import 'package:drift/drift.dart';

import 'sync_backfill.dart' show syncedTableNames, isCustomFilteredTableNames;

/// v25 migration step: installs the SQLite triggers that populate
/// `pending_sync_ops` — the outbox `SyncService` drains — on every write to a
/// synced table. No repository code is touched; every insert/update/delete
/// already goes through Drift's generated SQL, which these triggers hook.
///
/// Three triggers per table:
///  - `AFTER INSERT` / `AFTER UPDATE` enqueue an `upsert` op keyed on the
///    row's own `sync_uuid`.
///  - `AFTER DELETE` enqueues a `delete` op keyed on the deleted row's
///    `sync_uuid` — the fallback for any hard `DELETE FROM` a repository
///    still issues on a synced table (soft-deletes already route through
///    `deletedAt`, which the UPDATE trigger already covers).
///
/// All three use `ON CONFLICT(entity_type, entity_id) DO UPDATE` so rapid
/// repeated edits before a push coalesce into one outbox row instead of
/// stacking up — this is also why the outbox needs no payload column:
/// `SyncService` re-reads the row's current state from Drift at push time.
///
/// `user_id` is left NULL here — SQLite triggers have no auth context —
/// and is filled in by `SyncService` immediately before each push.
///
/// Wrapped per-table in try/catch, same as `tryAddColumn` elsewhere in the
/// migration chain: several existing schema-version tests reopen a
/// hand-rolled fixture that only stamps down a narrow slice of the schema
/// (e.g. `test/schema_v21_test.dart`, which never creates `gyms`), and this
/// runs unconditionally on every migration to v25+, not just for tables the
/// fixture happens to declare.
Future<void> installSyncTriggers(GeneratedDatabase db) async {
  // SQLite doesn't validate a trigger body's referenced tables at CREATE
  // TRIGGER time, only when the trigger actually fires — so on a fixture
  // that never creates `pending_sync_ops` at all (some schema-version tests
  // stamp down only a handful of tables), trigger creation would silently
  // "succeed" and then crash the very next INSERT into any synced table.
  // Bail out up front instead: no outbox table means nowhere to enqueue
  // into regardless.
  final outboxExists = await db
      .customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pending_sync_ops'",
      )
      .getSingleOrNull();
  if (outboxExists == null) return;

  for (final table in syncedTableNames) {
    try {
      final isCustomFiltered = isCustomFilteredTableNames.contains(table);
      // `recipes` has no `is_custom` column — every row is user-authored, so
      // it's listed for documentation but must not get an is_custom guard.
      final isCustomGuard = (isCustomFiltered && table != 'recipes')
          ? ' AND NEW.is_custom = 1'
          : '';

      // sync_uuid IS NOT NULL guards every trigger: `entity_id` is NOT NULL
      // on `pending_sync_ops`, so a row that (however it happened — a raw
      // SQL write, a pre-migration state) briefly has a null sync_uuid must
      // not crash the write that's touching it. A row with no sync_uuid
      // isn't syncable yet regardless; skipping the enqueue is correct, not
      // lossy.
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_outbox_ins_$table
        AFTER INSERT ON $table
        WHEN NEW.sync_uuid IS NOT NULL$isCustomGuard
        BEGIN
          INSERT INTO pending_sync_ops (entity_type, entity_id, operation, created_at)
          VALUES ('$table', NEW.sync_uuid, 'upsert', strftime('%s','now'))
          ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            operation = 'upsert', created_at = excluded.created_at;
        END;
      ''');

      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_outbox_upd_$table
        AFTER UPDATE ON $table
        WHEN NEW.sync_uuid IS NOT NULL$isCustomGuard
        BEGIN
          INSERT INTO pending_sync_ops (entity_type, entity_id, operation, created_at)
          VALUES ('$table', NEW.sync_uuid, 'upsert', strftime('%s','now'))
          ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            operation = 'upsert', created_at = excluded.created_at;
        END;
      ''');

      // No is_custom guard on delete: OLD.is_custom is the row being
      // removed, and a hard delete of even a stray seeded row must not
      // leave a dangling outbox entry pointing at nothing — cheap to
      // enqueue, SyncService's push simply finds no local row and treats it
      // as already-gone.
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_outbox_del_$table
        AFTER DELETE ON $table
        WHEN OLD.sync_uuid IS NOT NULL
        BEGIN
          INSERT INTO pending_sync_ops (entity_type, entity_id, operation, created_at)
          VALUES ('$table', OLD.sync_uuid, 'delete', strftime('%s','now'))
          ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            operation = 'delete', created_at = excluded.created_at;
        END;
      ''');
    } catch (_) {
      // Table doesn't exist on this fixture; see doc comment above.
    }
  }
}
