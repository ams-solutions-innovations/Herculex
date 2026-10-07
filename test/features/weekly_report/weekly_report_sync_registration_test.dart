// Phase 29 (RPT-01): guards that `weekly_reports` is fully registered for sync.
// Half-registration fails silently (rows never leave the device, or the outbox
// never sees them), so each registration point is asserted and an insert must
// actually produce an outbox row. Modelled on test/tdee_sync_registration_test.
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weekly_reports is in the sync registries', () {
    expect(syncedTableNames, contains('weekly_reports'));
    expect(syncTableOrder, contains('weekly_reports'));

    final spec = syncTableSpecsByName['weekly_reports'];
    expect(spec, isNotNull);
    expect(spec!.dateTimeColumns, containsAll(['generated_at', 'viewed_at']));
  });

  test('a fresh database has the weekly_reports sync_uuid index', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_sync_uuid_weekly_reports'",
        )
        .get();
    expect(index, hasLength(1));
  });

  test('inserting a weekly report enqueues an upsert outbox row', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    await db
        .into(db.weeklyReports)
        .insert(
          WeeklyReportsCompanion.insert(
            isoYear: 2026,
            isoWeek: 40,
            weekStartIso: '2026-09-28',
            payloadJson: '{}',
          ),
        );

    final stored = await db.select(db.weeklyReports).getSingle();
    expect(stored.syncUuid, isNotNull);

    final ops = await db
        .customSelect(
          'SELECT entity_id, operation FROM pending_sync_ops '
          "WHERE entity_type = 'weekly_reports'",
        )
        .get();
    expect(ops, hasLength(1));
    expect(ops.single.read<String>('entity_id'), stored.syncUuid);
    expect(ops.single.read<String>('operation'), 'upsert');
  });
}
