// RB-04 Phase 4: schema tooling. Verifies the hand-written `tables.dart`
// declarations (as materialized by `AppDatabase`) match the schema drift_dev
// dumped to `drift_schemas/drift_schema_v46.json`. `schema dump` only
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

  test('current schema matches the v46 drift_schemas snapshot', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  test('upgrades cleanly from a generated v45 fixture to v46', () async {
    final connection = await verifier.startAt(45);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final columns = await db
        .customSelect('PRAGMA table_info(herculex_ai_program_briefs)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(<String>[
        'id',
        'program_id',
        'brief_json',
        'source',
        'knowledge_version',
        'model_version',
        'confirmed_at',
        'active',
        'sync_uuid',
      ]),
    );

    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_sync_uuid_herculex_ai_program_briefs'",
        )
        .get();
    expect(index, hasLength(1));

    // The outbox trigger installed by installSyncTriggers: without it an
    // upgraded install would never enqueue herculex_ai_program_briefs rows.
    final triggers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND tbl_name = 'herculex_ai_program_briefs'",
        )
        .get();
    expect(triggers, isNotEmpty);
  });

  test('upgrades cleanly from a generated v44 fixture to v45', () async {
    final connection = await verifier.startAt(44);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final columns = await db
        .customSelect('PRAGMA table_info(tdee_estimates)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(<String>[
        'date_iso',
        'estimated_at',
        'method',
        'confidence',
        'window_days',
        'kcal',
        'observed_qualified',
        'inputs_json',
        'sync_uuid',
      ]),
    );

    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_sync_uuid_tdee_estimates'",
        )
        .get();
    expect(index, hasLength(1));

    // The outbox trigger installed by installSyncTriggers: without it an
    // upgraded install would never enqueue tdee_estimates rows.
    final triggers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND tbl_name = 'tdee_estimates'",
        )
        .get();
    expect(triggers, isNotEmpty);
  });

  test('upgrades cleanly from a generated v43 fixture to v44', () async {
    final connection = await verifier.startAt(43);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final programExerciseSlotColumns = await db
        .customSelect('PRAGMA table_info(program_exercise_slots)')
        .get();
    expect(
      programExerciseSlotColumns.map((row) => row.read<String>('name')),
      contains('session_segment'),
    );

    final programDayExerciseColumns = await db
        .customSelect('PRAGMA table_info(program_day_exercises)')
        .get();
    final programDayExerciseColumnNames = programDayExerciseColumns.map(
      (row) => row.read<String>('name'),
    );
    expect(programDayExerciseColumnNames, contains('session_segment'));
    expect(programDayExerciseColumnNames, contains('superset_group'));

    final workoutExerciseColumns = await db
        .customSelect('PRAGMA table_info(workout_exercises)')
        .get();
    expect(
      workoutExerciseColumns.map((row) => row.read<String>('name')),
      contains('planned_session_segment'),
    );
  });

  test('upgrades cleanly from a generated v42 fixture to v43', () async {
    final connection = await verifier.startAt(42);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final programDayExerciseColumns = await db
        .customSelect('PRAGMA table_info(program_day_exercises)')
        .get();
    expect(
      programDayExerciseColumns.map((row) => row.read<String>('name')),
      contains('prescription_codec_json'),
    );

    final programColumns = await db
        .customSelect('PRAGMA table_info(programs)')
        .get();
    expect(
      programColumns.map((row) => row.read<String>('name')),
      contains('allow_time_saving_set_techniques'),
    );

    final workoutExerciseColumns = await db
        .customSelect('PRAGMA table_info(workout_exercises)')
        .get();
    expect(
      workoutExerciseColumns.map((row) => row.read<String>('name')),
      contains('planned_allows_advanced_techniques'),
    );
  });

  test('upgrades cleanly from a generated v41 fixture to v42', () async {
    final connection = await verifier.startAt(41);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final columns = await db
        .customSelect('PRAGMA table_info(program_slot_explanations)')
        .get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();
    expect(
      columnNames,
      containsAll(<String>[
        'id',
        'slot_id',
        'week_index',
        'chosen_exercise_id',
        'status',
        'rationale',
        'excluded_json',
      ]),
    );

    final syncIndexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'program_slot_explanations'",
        )
        .get();
    expect(
      syncIndexes.map((row) => row.read<String>('name')),
      isNot(contains('idx_sync_uuid_program_slot_explanations')),
    );
  });

  // There is no drift_schema_v39.json or drift_schema_v40.json: `schema
  // dump` only captures the *current* version (see the file header comment),
  // and by the time this plan (17-01) ran, no commit's `schemaVersion => 39`
  // or `=> 40` had ever been dumped — the two per-version replay tests that
  // used to live here (`startAt(39)`, `startAt(40)`) referenced generated
  // fixture classes that were never committed, so `schema.dart` could not
  // resolve them. v38 is the newest fixture that can be replayed from; this
  // single test covers the v39, v40 and v41 steps together, same reasoning
  // as the v32 -> v34 combined replay above.
  test('upgrades cleanly from a generated v38 fixture to v42', () async {
    final connection = await verifier.startAt(38);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>[
        'program_exercise_slots',
        'program_slot_pool_members',
        'rotation_assignments',
        'prescription_templates',
        'physique_programming_profiles',
        'exercise_preferences',
        'gym_equipment',
        'program_slot_explanations',
      ]),
    );

    final setColumns = await db
        .customSelect('PRAGMA table_info(set_entries)')
        .get();
    expect(
      setColumns.map((row) => row.read<String>('name')),
      containsAll(<String>[
        'planned_reps_min',
        'planned_reps_max',
        'planned_weight_kg',
        'planned_rpe_x10',
        'planned_rir',
        'planned_percent_of1_rm',
        'planned_intent',
      ]),
    );

    final columns = await db
        .customSelect('PRAGMA table_info(exercise_catalog)')
        .get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();
    expect(
      columnNames,
      containsAll(<String>[
        'disciplines',
        'prerequisite_slugs',
        'scaling_group',
        'scaling_order',
        'competition_anchor',
        'specialization_tags',
      ]),
    );

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_exercise_catalog_scaling'",
        )
        .get();
    expect(indexes, isNotEmpty);
  });

  // With two dumped snapshots (v23, v24) now on disk, startAt(23) has real
  // fixture data to replay from for the first time — this exercises the real
  // onUpgrade(23 -> 24) chain against a drift-generated v23 schema, rather
  // than only comparing the current schema to its own dump.
  test('upgrades cleanly from a generated v23 fixture', () async {
    final connection = await verifier.startAt(23);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // Phase 10 sync (v25) touches every synced table at once — this is the
  // widest single migration step yet, so it gets its own generated-fixture
  // replay in addition to the v23 one above.
  test('upgrades cleanly from a generated v24 fixture', () async {
    final connection = await verifier.startAt(24);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // The v26 step used to create three local-only assisted-rep-tracking
  // tables here; the feature was removed and that step is now a no-op (see
  // database.dart). Same generated-fixture replay as the v23/v24 blocks
  // above, one step narrower.
  test('upgrades cleanly from a generated v25 fixture', () async {
    final connection = await verifier.startAt(25);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // UI rework Phase 6 (v27) adds the fasting_schedules table. Same
  // generated-fixture replay, one step narrower still.
  test('upgrades cleanly from a generated v26 fixture', () async {
    final connection = await verifier.startAt(26);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // UI rework Phase 8 (v28) adds start_time_minutes to program_days and
  // scheduled_workouts. Same generated-fixture replay, one step narrower
  // still.
  test('upgrades cleanly from a generated v27 fixture', () async {
    final connection = await verifier.startAt(27);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // Phase 11 Gym Buddy (v29) adds two local-only buddy mirror tables plus
  // workout_sessions.buddy_session_id. Same generated-fixture replay, one
  // step narrower still.
  test('upgrades cleanly from a generated v28 fixture', () async {
    final connection = await verifier.startAt(28);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // The v30 step used to add rep_tracking_settings.auto_count_enabled here;
  // like v26 above, it is now a no-op on the table that no longer exists.
  // Same generated-fixture replay, one step narrower still.
  test('upgrades cleanly from a generated v29 fixture', () async {
    final connection = await verifier.startAt(29);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // GSD 12-04 (v31): set_entries gains duration_seconds, distance_m and
  // calories. The narrowest replay of all — one step, three nullable columns
  // on a table that every synced-table trigger and index already covers.
  test('upgrades cleanly from a generated v30 fixture', () async {
    final connection = await verifier.startAt(30);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // Recovery page (v32): joint_pain_logs, a new synced table. Same
  // generated-fixture replay, one step narrower still.
  test('upgrades cleanly from a generated v31 fixture', () async {
    final connection = await verifier.startAt(31);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // v33 (workout_sessions.photo_path + calories_burned) and v34 (the two
  // circuit tables) shipped in the same commit, so no build ever carried v33
  // and no device can be sitting on it — v32 -> v34 is the only real upgrade
  // path, and this replay is the one that exercises both steps together.
  //
  // There is deliberately no `drift_schema_v33.json`: `schema dump` captures
  // only the *current* version, and no commit ever had `schemaVersion => 33`
  // to dump from. Same limitation as the missing v1-v22 snapshots above.
  //
  // Until this test existed, the v33 and v34 migration steps had never been
  // executed by anything — the whole suite still validated against v32, which
  // is why 24 tests were failing with "unexpected entries: photo_path,
  // calories_burned".
  test('upgrades cleanly from a generated v32 fixture', () async {
    final connection = await verifier.startAt(32);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // v35 (achievements + the two Hercul tables), v36 (fasting_stages) and v37
  // (double progression) shipped without their own dumps, so v34 is the
  // newest fixture that can be replayed from — this one replay covers all
  // three steps at once. Same reason there is no v33 snapshot above.
  //
  // v37 is the first of the three that is an addColumn rather than a
  // createTable, which is the case worth pinning: the six columns land on an
  // exercise_progressions table that already has rows, so a mistake here
  // surfaces as a migration failure rather than an empty-table no-op.
  test('upgrades cleanly from a generated v34 fixture', () async {
    final connection = await verifier.startAt(34);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);
  });

  // v38 removes assisted rep tracking. drift_schema_v37.json was dumped
  // before that removal, so — unlike every replay above, which only ever
  // exercises a *no-op* rep-tracking step — this is the one fixture that
  // actually has rep_tracking_settings/rep_tracking_exercise_prefs/
  // rep_set_observations present, which is what makes it the real test of
  // the `DROP TABLE IF EXISTS` step rather than a vacuous pass against
  // tables that were never there to begin with.
  test('upgrades cleanly from a generated v37 fixture, dropping the removed '
      'rep-tracking tables', () async {
    final connection = await verifier.startAt(37);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 46);

    final remaining = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('rep_tracking_settings', "
          "'rep_tracking_exercise_prefs', 'rep_set_observations')",
        )
        .get();
    expect(remaining, isEmpty);
  });
}
