import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

/// Every table SyncService syncs needs the same server-side wiring, and a
/// table that misses one fails quietly:
///
/// * no `set_updated_at` clock - the delta pull never sees its edits;
/// * no tombstone trigger - a HARD delete on one device never reaches the
///   others (a delta pull cannot see a row that no longer exists);
/// * not in the realtime publication - its channel is dead and only the
///   5-minute poll notices changes;
/// * no RLS - owner-only access is not enforced.
///
/// The migrations wire most tables in `foreach t in array tables` loops, so
/// this reads the SQL as text: a table counts as wired when a statement names
/// it, or when its quoted name appears in a migration that contains the
/// matching wiring.
void main() {
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  String normalize(String sql) => sql
      .toLowerCase()
      .replaceAll(RegExp(r'--[^\n]*'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  final sqlByFile = {
    for (final file in migrations)
      file.path: normalize(file.readAsStringSync()),
  };
  final allSql = sqlByFile.values.join('\n');

  bool namedInLoopMigration(String table, String loopMarker) => sqlByFile.values
      .any((sql) => sql.contains(loopMarker) && sql.contains("'$table'"));

  final tables = [for (final spec in syncTableSpecs) spec.table];

  test('the registry is not empty and the migrations were found', () {
    expect(tables, isNotEmpty);
    expect(migrations, isNotEmpty);
  });

  group('every synced table', () {
    for (final table in tables) {
      group(table, () {
        test('exists in Postgres', () {
          expect(
            RegExp(
              'create table (if not exists )?(public\\.)?$table\\b',
            ).hasMatch(allSql),
            isTrue,
            reason: 'no migration creates $table',
          );
        });

        test('has row level security', () {
          final direct = RegExp(
            'alter table (public\\.)?$table enable row level security',
          ).hasMatch(allSql);
          expect(
            direct || namedInLoopMigration(table, 'enable row level security'),
            isTrue,
            reason: '$table is not owner-only',
          );
        });

        test('has the updated_at clock trigger', () {
          final direct = RegExp(
            't_set_updated_at_$table\\b|on (public\\.)?$table for each row execute function (public\\.)?set_updated_at',
          ).hasMatch(allSql);
          expect(
            direct || namedInLoopMigration(table, 'set_updated_at'),
            isTrue,
            reason: 'edits to $table would never reach a delta pull',
          );
        });

        test('records a tombstone when a row is hard-deleted', () {
          final direct = RegExp(
            't_record_tombstone_$table\\b|on (public\\.)?$table for each row execute function (public\\.)?record_sync_tombstone',
          ).hasMatch(allSql);
          expect(
            direct || namedInLoopMigration(table, 'record_sync_tombstone'),
            isTrue,
            reason: 'a hard delete of a $table row would stay on other devices',
          );
        });

        test('is in the realtime publication', () {
          final direct = RegExp(
            'alter publication supabase_realtime add table (public\\.)?$table\\b',
          ).hasMatch(allSql);
          expect(
            direct || namedInLoopMigration(table, 'supabase_realtime'),
            isTrue,
            reason: '$table changes only arrive with the 5-minute poll',
          );
        });
      });
    }
  });

  test('the v39 planner wiring migration covers all seven tables', () {
    final sql = sqlByFile.entries
        .firstWhere((e) => e.key.endsWith('_v39_planner_sync_wiring.sql'))
        .value;
    for (final table in const [
      'prescription_templates',
      'physique_programming_profiles',
      'program_exercise_slots',
      'program_slot_pool_members',
      'rotation_assignments',
      'exercise_preferences',
      'gym_equipment',
    ]) {
      expect(sql, contains("'$table'"));
    }
    expect(sql, contains('record_sync_tombstone'));
    expect(sql, contains('supabase_realtime'));
  });
}
