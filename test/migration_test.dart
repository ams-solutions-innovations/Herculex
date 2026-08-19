// RB-04 Phase 4: schema tooling. Verifies the hand-written `tables.dart`
// declarations (as materialized by `AppDatabase`) match the schema drift_dev
// dumped to `drift_schemas/drift_schema_v31.json`. `schema dump` only
// captures the *current* version — there is no retroactive v1-v22 snapshot —
// so this only proves "the code matches what was dumped", not a full
// migration-chain replay. Re-run `dart run drift_dev schema dump
// lib/data/local/database.dart drift_schemas/` and `dart run drift_dev
// schema generate drift_schemas/ test/generated_migrations/` on every
// schemaVersion bump, and this test's expected version along with it.
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'generated_migrations/schema.dart';
import 'support/test_database.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('current schema matches the v31 drift_schemas snapshot', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // With two dumped snapshots (v23, v24) now on disk, startAt(23) has real
  // fixture data to replay from for the first time — this exercises the real
  // onUpgrade(23 -> 24) chain against a drift-generated v23 schema, rather
  // than only comparing the current schema to its own dump.
  test('upgrades cleanly from a generated v23 fixture', () async {
    final connection = await verifier.startAt(23);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // Phase 10 sync (v25) touches every synced table at once — this is the
  // widest single migration step yet, so it gets its own generated-fixture
  // replay in addition to the v23 one above.
  test('upgrades cleanly from a generated v24 fixture', () async {
    final connection = await verifier.startAt(24);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // Phase 10 assisted rep tracking (v26) adds three local-only tables. Same
  // generated-fixture replay as the v23/v24 blocks above, one step narrower.
  test('upgrades cleanly from a generated v25 fixture', () async {
    final connection = await verifier.startAt(25);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // UI rework Phase 6 (v27) adds the fasting_schedules table. Same
  // generated-fixture replay, one step narrower still.
  test('upgrades cleanly from a generated v26 fixture', () async {
    final connection = await verifier.startAt(26);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // UI rework Phase 8 (v28) adds start_time_minutes to program_days and
  // scheduled_workouts. Same generated-fixture replay, one step narrower
  // still.
  test('upgrades cleanly from a generated v27 fixture', () async {
    final connection = await verifier.startAt(27);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // Phase 11 Gym Buddy (v29) adds two local-only buddy mirror tables plus
  // workout_sessions.buddy_session_id. Same generated-fixture replay, one
  // step narrower still.
  test('upgrades cleanly from a generated v28 fixture', () async {
    final connection = await verifier.startAt(28);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // Assisted rep tracking's global switch (v30): rep_tracking_settings gains
  // auto_count_enabled. Same generated-fixture replay, one step narrower
  // still.
  test('upgrades cleanly from a generated v29 fixture', () async {
    final connection = await verifier.startAt(29);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });

  // GSD 12-04 (v31): set_entries gains duration_seconds, distance_m and
  // calories. The narrowest replay of all — one step, three nullable columns
  // on a table that every synced-table trigger and index already covers.
  test('upgrades cleanly from a generated v30 fixture', () async {
    final connection = await verifier.startAt(30);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 31);
  });
}
