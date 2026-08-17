// UI rework Phase 8: v27 -> v28 adds nullable start_time_minutes to
// program_days and scheduled_workouts and touches nothing else. Follows the
// per-version migration-test idiom established by `test/schema_v27_test.dart`.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v27.dart' as v27;
import 'generated_migrations/schema_v28.dart' as v28;

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test(
    'v27 -> v28 adds start_time_minutes to program_days and '
    'scheduled_workouts, and preserves pre-existing rows in untouched tables',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 27,
        newVersion: 28,
        createOld: v27.DatabaseAtV27.new,
        createNew: v28.DatabaseAtV28.new,
        openTestedDatabase: AppDatabase.forTesting,
        createItems: (batch, oldDb) {
          // `gyms` is untouched by v28; the canary proving the migration is
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

          for (final table in ['program_days', 'scheduled_workouts']) {
            final columns = await newDb
                .customSelect('PRAGMA table_info($table)')
                .get();
            final names = columns.map((r) => r.read<String>('name')).toSet();
            expect(
              names,
              contains('start_time_minutes'),
              reason: '$table must gain start_time_minutes',
            );
          }
        },
      );
    },
  );
}
