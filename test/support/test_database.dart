import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

/// Opens an in-memory [AppDatabase] for tests.
///
/// Since RB-04 Phase 3, `AppDatabase`'s own `beforeOpen` always issues
/// `PRAGMA foreign_keys = ON`, so every test gets real enforcement by
/// default without this helper doing anything special. `foreignKeys: false`
/// is kept for tests that specifically want to prove a repository's delete
/// path is correct even when enforcement is off (mirroring pre-Phase-3
/// production behavior) — it forces the migration to run first (a trivial
/// query, needed because `beforeOpen` itself already turned the pragma on
/// by then) and then flips it back off.
Future<AppDatabase> openTestDatabase({bool foreignKeys = true}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  // Force beforeOpen (and the onCreate/onUpgrade migration it follows) to
  // run before we potentially override its pragma.
  await db.customSelect('SELECT 1').getSingle();
  if (!foreignKeys) {
    await db.customStatement('PRAGMA foreign_keys = OFF');
  }
  return db;
}

/// One row of `PRAGMA foreign_key_check` output: a child row that violates
/// one of its table's foreign keys.
class ForeignKeyViolation {
  const ForeignKeyViolation({
    required this.table,
    required this.rowId,
    required this.parent,
    required this.fkId,
  });

  final String table;
  final int? rowId;
  final String parent;
  final int fkId;

  @override
  String toString() =>
      'ForeignKeyViolation(table: $table, rowId: $rowId, parent: $parent, '
      'fkId: $fkId)';
}

/// Wraps `PRAGMA foreign_key_check`, which enumerates every row across the
/// whole database that currently violates a declared foreign key —
/// regardless of whether `PRAGMA foreign_keys` is on.
Future<List<ForeignKeyViolation>> foreignKeyViolations(
  GeneratedDatabase db,
) async {
  final rows = await db.customSelect('PRAGMA foreign_key_check').get();
  return [
    for (final row in rows)
      ForeignKeyViolation(
        table: row.read<String>('table'),
        rowId: row.data['rowid'] as int?,
        parent: row.read<String>('parent'),
        fkId: row.read<int>('fkid'),
      ),
  ];
}

/// Matcher-style assertion for [foreignKeyViolations] results.
void expectNoForeignKeyViolations(List<ForeignKeyViolation> violations) {
  expect(
    violations,
    isEmpty,
    reason: 'Expected no foreign key violations, found: $violations',
  );
}
