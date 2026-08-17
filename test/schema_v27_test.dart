// UI rework Phase 6: v26 -> v27 adds the fasting_schedules table (synced —
// SyncColumns + SyncTombstone) and touches nothing else. Follows the
// per-version migration-test idiom established by `test/schema_v26_test.dart`.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v26.dart' as v26;
import 'generated_migrations/schema_v27.dart' as v27;

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test(
    'v26 -> v27 creates fasting_schedules and preserves pre-existing rows '
    'in untouched tables',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 26,
        newVersion: 27,
        createOld: v26.DatabaseAtV26.new,
        createNew: v27.DatabaseAtV27.new,
        openTestedDatabase: AppDatabase.forTesting,
        createItems: (batch, oldDb) {
          // `gyms` is untouched by v27; the canary proving the migration is
          // purely additive.
          batch.insertAll(oldDb.gyms, [
            RawValuesInsertable({
              'id': const Variable<int>(1),
              'name': const Variable<String>('Herculex Test Gym'),
            }),
          ]);
        },
        validateItems: (newDb) async {
          final gym = await newDb
              .customSelect('SELECT name FROM gyms WHERE id = 1')
              .getSingle();
          expect(gym.read<String>('name'), 'Herculex Test Gym');

          final tableRows = await newDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get();
          final tableNames = tableRows.map((r) => r.read<String>('name')).toSet();
          expect(tableNames, contains('fasting_schedules'));

          // New table starts empty.
          final count = await newDb
              .customSelect('SELECT COUNT(*) AS c FROM fasting_schedules')
              .getSingle();
          expect(count.read<int>('c'), 0);

          // Synced table: sync_uuid unique index + outbox triggers must
          // exist, same as every other v25+ synced table.
          final indexRows = await newDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index' "
                "AND tbl_name = 'fasting_schedules'",
              )
              .get();
          expect(
            indexRows.map((r) => r.read<String>('name')),
            contains('idx_sync_uuid_fasting_schedules'),
          );

          final triggerRows = await newDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'trigger' "
                "AND tbl_name = 'fasting_schedules'",
              )
              .get();
          final triggerNames = triggerRows
              .map((r) => r.read<String>('name'))
              .toSet();
          expect(triggerNames, contains('trg_outbox_ins_fasting_schedules'));
          expect(triggerNames, contains('trg_outbox_upd_fasting_schedules'));
          expect(triggerNames, contains('trg_outbox_del_fasting_schedules'));
        },
      );
    },
  );
}
