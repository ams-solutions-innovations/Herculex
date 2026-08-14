// REP-04 / T-10-01: the three rep-tracking tables are local-only.
//
// This is the *positive* assertion the plan calls for. A source grep over
// `tables.dart` would prove only that the tables declare no `SyncColumns`;
// it would say nothing about a trigger installed at runtime by
// `installSyncTriggers`, which writes DDL from a name list rather than from
// the table declarations. So this queries `sqlite_master` on a fully
// migrated database instead, and separately asserts the names are absent
// from both sync source lists.
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

import 'support/test_database.dart';

const _repTables = <String>[
  'rep_tracking_settings',
  'rep_tracking_exercise_prefs',
  'rep_set_observations',
];

void main() {
  group('rep tracking tables are local-only', () {
    test('no outbox trigger exists on any of the three tables', () async {
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
          _repTables,
          isNot(contains(row.read<String>('tbl_name'))),
          reason:
              'trigger ${row.read<String>('name')} would push rep-tracking '
              'rows into the sync outbox',
        );
      }
    });

    test('the three tables appear in neither sync list', () {
      for (final table in _repTables) {
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
      'rep_set_observations has no column able to hold a raw sample array',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);

        final columns = await db
            .customSelect('PRAGMA table_info(rep_set_observations)')
            .get();
        final names = columns.map((r) => r.read<String>('name')).toSet();

        // T-10-02: only derived features and confirmed outcomes persist.
        expect(names, contains('features_json'));
        for (final forbidden in const [
          'samples',
          'samples_json',
          'raw_samples',
          'raw_samples_json',
          'sample_blob',
          'accelerometer_samples',
        ]) {
          expect(names, isNot(contains(forbidden)));
        }
        // No BLOB column at all — a blob is the only shape a raw sample
        // array could plausibly take without an obvious name.
        expect(
          columns.map((r) => r.read<String>('type').toUpperCase()),
          isNot(contains('BLOB')),
        );
      },
    );
  });
}
