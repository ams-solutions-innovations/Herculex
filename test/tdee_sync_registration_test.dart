// Phase 28 (TDEE-05): guards that `tdee_estimates` is fully registered for
// sync. Half-registration fails silently (rows never leave the device, or the
// outbox never sees them), so each registration point is asserted, and an
// insert must actually produce an outbox row. Inverse of
// `test/buddy/buddy_local_only_test.dart`, which guards a table that must NOT
// sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tdee_estimates is in the sync registries', () {
    expect(syncedTableNames, contains('tdee_estimates'));
    expect(syncTableOrder, contains('tdee_estimates'));

    final spec = syncTableSpecsByName['tdee_estimates'];
    expect(spec, isNotNull);
    expect(spec!.dateTimeColumns, contains('estimated_at'));
  });

  test('a fresh database has the sync_uuid unique index', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_sync_uuid_tdee_estimates'",
        )
        .get();
    expect(index, hasLength(1));
  });

  test('inserting an estimate enqueues an outbox row', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    await db
        .into(db.tdeeEstimates)
        .insert(
          TdeeEstimatesCompanion.insert(
            dateIso: '2026-09-28',
            method: 'observed',
            confidence: 'high',
            windowDays: 28,
            kcal: 2500,
            inputsJson: '{}',
          ),
        );

    final stored = await db.select(db.tdeeEstimates).getSingle();
    expect(stored.syncUuid, isNotNull);

    final ops = await db
        .customSelect(
          'SELECT entity_id, operation FROM pending_sync_ops '
          "WHERE entity_type = 'tdee_estimates'",
        )
        .get();
    expect(ops, hasLength(1));
    expect(ops.single.read<String>('entity_id'), stored.syncUuid);
    expect(ops.single.read<String>('operation'), 'upsert');
  });
}
