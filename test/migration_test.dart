// RB-04 Phase 4: schema tooling. Verifies the hand-written `tables.dart`
// declarations (as materialized by `AppDatabase`) match the schema drift_dev
// dumped to `drift_schemas/drift_schema_v23.json`. `schema dump` only
// captures the *current* version — there is no retroactive v1-v22 snapshot —
// so this only proves "the code matches what was dumped", not a full
// migration-chain replay. Re-run `dart run drift_dev schema dump
// lib/data/local/database.dart drift_schemas/` and `dart run drift_dev
// schema generate drift_schemas/ test/generated_migrations/` on every
// schemaVersion bump, and this test's expected version along with it.
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';
import 'support/test_database.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('current schema matches the v23 drift_schemas snapshot', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 23);
  });
}
