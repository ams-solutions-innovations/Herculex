import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

import 'support/test_database.dart';

/// A single declared foreign key edge, as reported by
/// `PRAGMA foreign_key_list('<table>')`.
class _FkEdge {
  const _FkEdge(this.table, this.from, this.parent, this.to, this.onDelete);

  final String table;
  final String from;
  final String parent;
  final String to;
  final String onDelete;

  @override
  String toString() => "('$table', '$from', '$parent', '$to', '$onDelete')";

  @override
  bool operator ==(Object other) =>
      other is _FkEdge &&
      other.table == table &&
      other.from == from &&
      other.parent == parent &&
      other.to == to &&
      other.onDelete == onDelete;

  @override
  int get hashCode => Object.hash(table, from, parent, to, onDelete);
}

/// The full, hard-coded inventory of every foreign key declared in
/// `lib/data/local/tables.dart` (emitted in `database.g.dart`), captured by
/// `PRAGMA foreign_key_list` against a freshly-migrated database. 20 CASCADE
/// + 10 RESTRICT + 8 SET NULL = 38 edges. Any future `tables.dart` edit that
/// adds, removes, or changes the `onDelete` action of an edge must update
/// this list deliberately — that is the point of the test.
const _expectedEdges = <_FkEdge>[
  _FkEdge('buddy_sessions_local', 'workout_session_id', 'workout_sessions', 'id', 'CASCADE'),
  _FkEdge('buddy_choreography_slots', 'workout_exercise_id', 'workout_exercises', 'id', 'CASCADE'),
  _FkEdge('exercise_aliases', 'exercise_id', 'exercise_catalog', 'id', 'CASCADE'),
  _FkEdge('exercise_muscles', 'exercise_id', 'exercise_catalog', 'id', 'CASCADE'),
  _FkEdge('exercise_progressions', 'exercise_id', 'exercise_catalog', 'id', 'CASCADE'),
  _FkEdge('food_entries', 'recipe_id', 'recipes', 'id', 'RESTRICT'),
  _FkEdge('food_entries', 'food_id', 'foods', 'id', 'RESTRICT'),
  _FkEdge('food_micros', 'food_id', 'foods', 'id', 'CASCADE'),
  _FkEdge('machine_settings', 'gym_id', 'gyms', 'id', 'SET NULL'),
  _FkEdge('machine_settings', 'exercise_id', 'exercise_catalog', 'id', 'CASCADE'),
  _FkEdge('micro_workouts', 'exercise_id', 'exercise_catalog', 'id', 'RESTRICT'),
  _FkEdge('program_day_exercises', 'rotation_id', 'exercise_rotations', 'id', 'SET NULL'),
  _FkEdge('program_day_exercises', 'exercise_id', 'exercise_catalog', 'id', 'RESTRICT'),
  _FkEdge('program_day_exercises', 'program_day_id', 'program_days', 'id', 'CASCADE'),
  _FkEdge('program_days', 'template_id', 'workout_templates', 'id', 'SET NULL'),
  _FkEdge('program_days', 'program_week_id', 'program_weeks', 'id', 'CASCADE'),
  _FkEdge('program_weeks', 'program_id', 'programs', 'id', 'CASCADE'),
  _FkEdge('recipe_ingredients', 'food_id', 'foods', 'id', 'RESTRICT'),
  _FkEdge('recipe_ingredients', 'recipe_id', 'recipes', 'id', 'CASCADE'),
  _FkEdge('rotation_members', 'exercise_id', 'exercise_catalog', 'id', 'RESTRICT'),
  _FkEdge('rotation_members', 'rotation_id', 'exercise_rotations', 'id', 'CASCADE'),
  _FkEdge('scheduled_workouts', 'template_id_override', 'workout_templates', 'id', 'SET NULL'),
  _FkEdge('scheduled_workouts', 'program_id', 'programs', 'id', 'CASCADE'),
  _FkEdge('scheduled_workouts', 'completed_session_id', 'workout_sessions', 'id', 'SET NULL'),
  _FkEdge('scheduled_workouts', 'program_day_id', 'program_days', 'id', 'CASCADE'),
  _FkEdge('set_accessories', 'accessory_id', 'accessories', 'id', 'RESTRICT'),
  _FkEdge('set_accessories', 'set_entry_id', 'set_entries', 'id', 'CASCADE'),
  _FkEdge('set_bands', 'band_id', 'bands', 'id', 'RESTRICT'),
  _FkEdge('set_bands', 'set_entry_id', 'set_entries', 'id', 'CASCADE'),
  _FkEdge('set_entries', 'workout_exercise_id', 'workout_exercises', 'id', 'CASCADE'),
  _FkEdge('template_exercises', 'exercise_id', 'exercise_catalog', 'id', 'RESTRICT'),
  _FkEdge('template_exercises', 'template_id', 'workout_templates', 'id', 'CASCADE'),
  _FkEdge('template_sets', 'template_exercise_id', 'template_exercises', 'id', 'CASCADE'),
  _FkEdge('workout_exercises', 'exercise_id', 'exercise_catalog', 'id', 'RESTRICT'),
  _FkEdge('workout_exercises', 'session_id', 'workout_sessions', 'id', 'CASCADE'),
  _FkEdge('workout_sessions', 'micro_workout_id', 'micro_workouts', 'id', 'SET NULL'),
  _FkEdge('workout_sessions', 'gym_id', 'gyms', 'id', 'SET NULL'),
  _FkEdge('workout_templates', 'folder_id', 'workout_folders', 'id', 'SET NULL'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });
  tearDown(() async => db.close());

  test('PRAGMA foreign_keys is actually on', () async {
    // Written first and deliberately: if openTestDatabase() ever regresses
    // into a silent no-op (e.g. the pragma gets issued inside the migration
    // transaction again), every other assertion in this file would still
    // pass vacuously, because foreign_key_list/table_info reflect the
    // *declared* schema regardless of enforcement. This is the one
    // assertion that would actually catch that regression.
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.first, 1);
  });

  test('declared foreign key inventory matches exactly', () async {
    final tableNames = db.allTables.map((t) => t.actualTableName).toList();
    final actualEdges = <_FkEdge>[];
    for (final table in tableNames) {
      final rows = await db.customSelect(
        "PRAGMA foreign_key_list('$table')",
      ).get();
      for (final row in rows) {
        actualEdges.add(
          _FkEdge(
            table,
            row.read<String>('from'),
            row.read<String>('table'),
            row.read<String>('to'),
            row.read<String>('on_delete'),
          ),
        );
      }
    }

    // Compare as sets so ordering (which PRAGMA does not guarantee) doesn't
    // matter, while still catching duplicates via length.
    expect(
      actualEdges.length,
      _expectedEdges.length,
      reason:
          'Edge count changed — actual: $actualEdges\nexpected: $_expectedEdges',
    );
    expect(actualEdges.toSet(), _expectedEdges.toSet());
  });

  test('edge action counts are 20 CASCADE / 10 RESTRICT / 8 SET NULL', () {
    final byAction = <String, int>{};
    for (final edge in _expectedEdges) {
      byAction[edge.onDelete] = (byAction[edge.onDelete] ?? 0) + 1;
    }
    expect(byAction['CASCADE'], 20);
    expect(byAction['RESTRICT'], 10);
    expect(byAction['SET NULL'], 8);
  });

  test('every SET NULL edge targets a nullable column', () async {
    final setNullEdges = _expectedEdges.where((e) => e.onDelete == 'SET NULL');
    for (final edge in setNullEdges) {
      final columns = await db.customSelect(
        "PRAGMA table_info('${edge.table}')",
      ).get();
      final column = columns.singleWhere(
        (c) => c.read<String>('name') == edge.from,
        orElse: () => throw StateError(
          'Column ${edge.from} not found on ${edge.table}',
        ),
      );
      // table_info's "notnull" is 1 for NOT NULL columns, 0 for nullable.
      expect(
        column.read<int>('notnull'),
        0,
        reason:
            '${edge.table}.${edge.from} is ON DELETE SET NULL but declared '
            'NOT NULL — SQLite would reject the SET NULL at runtime',
      );
    }
  });
}
