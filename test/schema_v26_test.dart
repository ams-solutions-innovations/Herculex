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
import 'generated_migrations/schema_v26.dart' as v26;

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
        newVersion: 26,
        createOld: v25.DatabaseAtV25.new,
        createNew: v26.DatabaseAtV26.new,
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
