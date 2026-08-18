// Phase 11 Gym Buddy: v28 -> v29 adds two local-only buddy mirror tables
// (buddy_sessions_local, buddy_choreography_slots) and a nullable synced
// buddy_session_id column on workout_sessions, and touches nothing else.
// Follows the per-version migration-test idiom established by
// `test/schema_v28_test.dart`.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v28.dart' as v28;
import 'generated_migrations/schema_v29.dart' as v29;

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test(
    'v28 -> v29 adds the buddy mirror tables and workout_sessions.'
    'buddy_session_id, and preserves pre-existing rows in untouched tables',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 28,
        newVersion: 29,
        createOld: v28.DatabaseAtV28.new,
        createNew: v29.DatabaseAtV29.new,
        openTestedDatabase: AppDatabase.forTesting,
        createItems: (batch, oldDb) {
          // `gyms` is untouched by v29; the canary proving the migration is
          // purely additive, same as v28's.
          batch.insertAll(oldDb.gyms, [
            RawValuesInsertable({
              'id': const Variable<int>(1),
              'name': const Variable<String>('Herculex Test Gym'),
            }),
          ]);
          // A pre-existing session must survive the migration, and its new
          // buddy_session_id column must read as NULL afterwards — there is
          // no backfill value to invent for a session that predates buddy
          // sessions entirely.
          batch.insertAll(oldDb.workoutSessions, [
            RawValuesInsertable({
              'id': const Variable<int>(1),
              'started_at': Variable<DateTime>(DateTime(2026, 1, 1)),
            }),
          ]);
        },
        validateItems: (newDb) async {
          final gym = await newDb
              .customSelect('SELECT name FROM gyms WHERE id = 1')
              .getSingle();
          expect(gym.read<String>('name'), 'Herculex Test Gym');

          final session = await newDb
              .customSelect(
                'SELECT buddy_session_id FROM workout_sessions WHERE id = 1',
              )
              .getSingle();
          expect(
            session.data['buddy_session_id'],
            isNull,
            reason:
                'a pre-existing session predates buddy sessions and must '
                'not gain a value from thin air',
          );

          for (final table in [
            'buddy_sessions_local',
            'buddy_choreography_slots',
          ]) {
            // The table must exist and be queryable post-migration; an
            // empty result set (rather than an exception) is exactly what
            // "created but not backfilled" should look like.
            final rows = await newDb
                .customSelect('SELECT * FROM $table')
                .get();
            expect(rows, isEmpty);
          }
        },
      );
    },
  );
}
