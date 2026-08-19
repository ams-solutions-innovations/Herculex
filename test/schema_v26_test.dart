// Phase 10 (assisted rep tracking) migration step: v25 -> v26 adds three
// local-only tables and touches nothing else.
//
// Follows the per-version migration-test idiom established by
// `test/schema_v24_test.dart`, but replays against the drift-generated v25
// fixture rather than a hand-written DDL block — v25 is dumped, so there is
// no reason to re-declare its shape by hand.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v25.dart' as v25;
import 'generated_migrations/schema_v31.dart' as v31;

/// The three tables the v26 step creates. Local-only by design (REP-04).
const _repTables = <String>{
  'rep_tracking_settings',
  'rep_tracking_exercise_prefs',
  'rep_set_observations',
};

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test(
    'v25 -> v26 creates the three rep-tracking tables and preserves '
    'pre-existing rows in untouched tables',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 25,
        // Validated against the *current* schema rather than against v26,
        // even though the v26 step is what this test is about. This pair of
        // lines moves with every `schemaVersion` bump, exactly like
        // `migration_test.dart`'s `migrateAndValidate` targets.
        //
        // `Migrator.createTable` always materializes a table from its
        // present-day Dart definition, not from its shape at the version
        // whose block calls it — so the moment a later version adds a column
        // to a table the v26 block creates (v30 did, with
        // `rep_tracking_settings.auto_count_enabled`), replaying 25 -> 26
        // produces a table that legitimately does not match the dumped v26
        // snapshot. That is drift working as designed and the app is correct
        // either way: the v30 block's `tryAddColumn` swallows the
        // already-exists case precisely for this reason.
        //
        // Every assertion below is about the v26 step and survives the
        // retarget: the three tables are created, they start empty, and the
        // pre-existing `gyms` row is untouched. The same trap is waiting for
        // `schema_v27_test.dart` the day anything adds a column to
        // `fasting_schedules`.
        newVersion: 31,
        createOld: v25.DatabaseAtV25.new,
        createNew: v31.DatabaseAtV31.new,
        openTestedDatabase: AppDatabase.forTesting,
        createItems: (batch, oldDb) {
          // `gyms` is untouched by v26; it is the canary proving the
          // migration is purely additive.
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
              .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
              .get();
          final tableNames = tableRows
              .map((r) => r.read<String>('name'))
              .toSet();
          for (final table in _repTables) {
            expect(
              tableNames,
              contains(table),
              reason: 'v26 must create $table',
            );
          }

          // The new tables start empty: absence of a row is what "no consent
          // given" and "not enabled for this exercise" mean. A backfill here
          // would silently opt the user in.
          for (final table in _repTables) {
            final count = await newDb
                .customSelect('SELECT COUNT(*) AS c FROM $table')
                .getSingle();
            expect(count.read<int>('c'), 0, reason: '$table must be empty');
          }
        },
      );
    },
  );
}
