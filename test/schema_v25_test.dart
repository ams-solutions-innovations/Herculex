import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart'
    show backfillSyncUuids;

import 'generated_migrations/schema.dart';

/// Content-level assertions for the v24 -> v25 (Phase 10 sync) migration,
/// complementing `migration_test.dart`'s structural
/// `verifier.migrateAndValidate` check with behavior: does a v24 row that
/// predates sync actually get a usable `sync_uuid`, and do the outbox
/// triggers actually work once the migration has run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final verifier = SchemaVerifier(GeneratedHelper());

  test('reaches schema version 25', () async {
    final connection = await verifier.startAt(24);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 25);

    final row = await db.customSelect('PRAGMA user_version').getSingle();
    expect(row.data.values.first, 25);
  });

  test(
    'a pre-v25 row is backfilled with a non-null, unique sync_uuid',
    () async {
      final connection = await verifier.startAt(24);
      final db = AppDatabase.forTesting(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 25);

      // v24's generated fixture ships with no seed rows for `gyms`; insert
      // pre-migration-shaped rows directly to simulate an existing user.
      await db.customStatement(
        "INSERT INTO gyms (name, is_default, created_at) VALUES ('A', 0, 0)",
      );
      await db.customStatement(
        "INSERT INTO gyms (name, is_default, created_at) VALUES ('B', 0, 0)",
      );

      // These two rows were inserted after the migration ran, so they get a
      // sync_uuid via clientDefault immediately — not what this test is
      // about. Simulate a genuinely pre-migration row by clearing it, the
      // way a v24-era row would look before the v25 backfill runs.
      await db.customStatement('UPDATE gyms SET sync_uuid = NULL');
      final backfilled = await backfillSyncUuids(db, 'gyms');
      expect(backfilled, 2);

      final rows = await db.select(db.gyms).get();
      final uuids = rows.map((r) => r.syncUuid).toSet();
      expect(uuids, hasLength(2));
      expect(uuids, isNot(contains(null)));
    },
  );

  test('the outbox triggers fire after migrating from v24', () async {
    final connection = await verifier.startAt(24);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 25);

    await db.into(db.gyms).insert(GymsCompanion.insert(name: 'New Gym'));

    final ops = await db.select(db.pendingSyncOps).get();
    expect(ops, hasLength(1));
    expect(ops.single.entityType, 'gyms');
    expect(ops.single.operation, 'upsert');
  });

  test('foods/recipes keep their v24 deletedAt column untouched', () async {
    final connection = await verifier.startAt(24);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 25);

    // Column exists and is nullable/queryable post-migration — the v25
    // block must not have tried (and failed) to re-add it.
    final food = await db.customSelect(
      'SELECT deleted_at FROM foods LIMIT 1',
    ).getSingleOrNull();
    expect(food, isNull);
  });
}
