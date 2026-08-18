// BUD-02 / BUD-04 / T-11-15: the two Gym Buddy mirror tables are local-only.
//
// This is the *positive* assertion the plan calls for, cloned from
// `test/rep_local_only_test.dart`. A source grep over `tables.dart` would
// prove only that the tables declare no `SyncColumns`; it would say nothing
// about a trigger installed at runtime by `installSyncTriggers`, which
// writes DDL from a name list rather than from the table declarations. So
// this queries `sqlite_master` on a fully migrated database instead, and
// separately asserts the names are absent from both sync source lists.
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

import '../support/test_database.dart';

const _buddyTables = <String>[
  'buddy_sessions_local',
  'buddy_choreography_slots',
];

void main() {
  group('gym buddy mirror tables are local-only', () {
    test('no outbox trigger exists on either table', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            "SELECT name, tbl_name FROM sqlite_master WHERE type = 'trigger'",
          )
          .get();

      // Sanity: the outbox triggers really are installed on this database,
      // otherwise the assertion below would pass vacuously.
      expect(
        rows,
        isNotEmpty,
        reason: 'expected installSyncTriggers to have run on a fresh database',
      );

      for (final row in rows) {
        expect(
          _buddyTables,
          isNot(contains(row.read<String>('tbl_name'))),
          reason:
              'trigger ${row.read<String>('name')} would push a gym buddy '
              'mirror row into the sync outbox',
        );
      }
    });

    test('the two tables appear in neither sync list', () {
      for (final table in _buddyTables) {
        expect(
          syncedTableNames,
          isNot(contains(table)),
          reason: '$table must not be backfilled or trigger-wired',
        );
        expect(
          syncTableOrder,
          isNot(contains(table)),
          reason: '$table must not have a SyncTableSpec',
        );
      }
    });

    test(
      'buddy_sessions_local has none of the three SyncColumns/SyncTombstone '
      'columns',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);

        final columns = await db
            .customSelect('PRAGMA table_info(buddy_sessions_local)')
            .get();
        final names = columns.map((r) => r.read<String>('name')).toSet();

        for (final forbidden in const [
          'sync_uuid',
          'updated_at',
          'deleted_at',
        ]) {
          expect(
            names,
            isNot(contains(forbidden)),
            reason:
                '$forbidden would only exist if SyncColumns/SyncTombstone '
                'were mixed in',
          );
        }
      },
    );
  });
}
