import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';

/// A throwaway drift database used only to lay down a v20-shaped schema on a
/// file, so that reopening the file as [AppDatabase] (schemaVersion 21) runs the
/// real `onUpgrade` path from 20. Declaring no tables keeps `createAll()` a
/// no-op; the DDL below is the hand-written v20 shape of the four tables the
/// v21 migration touches.
class _V20Fixture extends GeneratedDatabase {
  _V20Fixture(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 20;
}

const _v20Ddl = <String>[
  '''
  CREATE TABLE workout_sessions (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    started_at INTEGER NOT NULL)
  ''',
  '''
  CREATE TABLE workout_templates (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL)
  ''',
  '''
  CREATE TABLE programs (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT NULL,
    weeks INTEGER NOT NULL DEFAULT 4,
    type TEXT NOT NULL DEFAULT 'block',
    progression_strategy TEXT NOT NULL DEFAULT 'volume',
    created_by_user INTEGER NOT NULL DEFAULT 1,
    archived INTEGER NOT NULL DEFAULT 0,
    periodization_model TEXT NOT NULL DEFAULT 'none')
  ''',
  '''
  CREATE TABLE program_weeks (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    program_id INTEGER NOT NULL REFERENCES programs (id) ON DELETE CASCADE,
    week_index INTEGER NOT NULL,
    adjustment_factor REAL NOT NULL DEFAULT 1.0,
    block_phase TEXT NULL,
    intensity_factor REAL NOT NULL DEFAULT 1.0)
  ''',
  '''
  CREATE TABLE program_days (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    program_week_id INTEGER NOT NULL
      REFERENCES program_weeks (id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL,
    name TEXT NOT NULL)
  ''',
  '''
  CREATE TABLE scheduled_workouts (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    date_iso TEXT NOT NULL,
    program_day_id INTEGER NOT NULL
      REFERENCES program_days (id) ON DELETE CASCADE,
    completed_session_id INTEGER NULL
      REFERENCES workout_sessions (id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'planned')
  ''',
];

/// Two programs so the backfill has something to disambiguate:
///   - program 1 "Block A", archived=0, one week, two days (Mon x2, Wed),
///     scheduled across three dates so occurrence indexes advance.
///   - program 2 "Block B", archived=1, one week, one day, one later date —
///     proves `is_active` skips archived programs even though it owns the
///     latest scheduled date overall.
const _v20Seed = <String>[
  "INSERT INTO programs (id, name, archived) VALUES (1, 'Block A', 0)",
  "INSERT INTO programs (id, name, archived) VALUES (2, 'Block B', 1)",
  'INSERT INTO program_weeks (id, program_id, week_index) VALUES (1, 1, 0)',
  'INSERT INTO program_weeks (id, program_id, week_index) VALUES (2, 2, 0)',
  // Two days share Monday — the program-day order backfill must rank them.
  "INSERT INTO program_days (id, program_week_id, day_of_week, name) "
      "VALUES (1, 1, 1, 'Push AM')",
  "INSERT INTO program_days (id, program_week_id, day_of_week, name) "
      "VALUES (2, 1, 1, 'Push PM')",
  "INSERT INTO program_days (id, program_week_id, day_of_week, name) "
      "VALUES (3, 1, 3, 'Legs')",
  "INSERT INTO program_days (id, program_week_id, day_of_week, name) "
      "VALUES (4, 2, 5, 'Full Body')",
  // Day 1 repeats over three weeks → occurrence 0, 1, 2.
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (1, '2026-01-05', 1)",
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (2, '2026-01-12', 1)",
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (3, '2026-01-19', 1)",
  // Same date as row 1, different day → the per-date order backfill must
  // produce 0 and 1 rather than two zeroes.
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (4, '2026-01-05', 2)",
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (5, '2026-01-07', 3)",
  // Archived program 2 owns the latest date in the table.
  "INSERT INTO scheduled_workouts (id, date_iso, program_day_id) "
      "VALUES (6, '2026-03-06', 4)",
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('herculex_v21_');
    dbFile = File('${tempDir.path}/app.sqlite');

    // 1. Lay down the v20 schema + fixture rows and stamp user_version = 20.
    final fixture = _V20Fixture(NativeDatabase(dbFile));
    for (final stmt in [..._v20Ddl, ..._v20Seed]) {
      await fixture.customStatement(stmt);
    }
    await fixture.close();

    // 2. Reopen as the real database — this runs onUpgrade(20 -> 21).
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db.customStatement('PRAGMA foreign_keys = ON');
    // Force the migration to run before the assertions.
    await db.select(db.programs).get();
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('v20 -> v21 migration', () {
    test('reaches schema version 22', () async {
      // The v20->v21 migration under test here runs as one step of the full
      // upgrade chain, which now continues on to 22 (Phase 1 of the
      // wear-sync remediation added the sessionUuid column) since this test
      // opens the real AppDatabase rather than stopping at v21.
      final row = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.data.values.first, 22);
    });

    test('added columns are readable with their defaults', () async {
      final program = await (db.select(
        db.programs,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(program.splitType, 'custom');
      expect(program.scheduleMode, 'weekly');
      expect(program.cycleLength, isNull);
      expect(program.daysPerWeek, isNull);

      final day = await (db.select(
        db.programDays,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(day.templateId, isNull);
      expect(day.cycleDayIndex, isNull);
      expect(day.isRest, isFalse);

      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(schedule.templateIdOverride, isNull);
    });

    test('backfills the owning program on every scheduled row', () async {
      final rows = await db.select(db.scheduledWorkouts).get();
      expect(rows.every((r) => r.programId != null), isTrue);
      expect(
        rows.where((r) => r.id <= 5).every((r) => r.programId == 1),
        isTrue,
      );
      expect(rows.singleWhere((r) => r.id == 6).programId, 2);
    });

    test('order index is dense within each date', () async {
      final rows = await db.select(db.scheduledWorkouts).get();
      final byDate = <String, List<int>>{};
      for (final r in rows) {
        (byDate[r.dateIso] ??= []).add(r.orderIndex);
      }
      for (final entry in byDate.entries) {
        final sorted = entry.value..sort();
        expect(
          sorted,
          List.generate(sorted.length, (i) => i),
          reason: 'date ${entry.key} should have dense 0..n-1 order indexes',
        );
      }
      // The two rows on 2026-01-05 specifically.
      final jan5 = rows.where((r) => r.dateIso == '2026-01-05').toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      expect(jan5.map((r) => r.orderIndex), [0, 1]);
    });

    test('occurrence index increments per repeat of a program day', () async {
      final rows = await db.select(db.scheduledWorkouts).get();
      final dayOne = rows.where((r) => r.programDayId == 1).toList()
        ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
      expect(dayOne.map((r) => r.occurrenceIndex), [0, 1, 2]);
      // A day scheduled once stays at occurrence 0.
      expect(rows.singleWhere((r) => r.programDayId == 3).occurrenceIndex, 0);
    });

    test('program days sharing a weekday get dense order indexes', () async {
      final days = await db.select(db.programDays).get();
      final monday = days.where((d) => d.programWeekId == 1 && d.dayOfWeek == 1)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      expect(monday.map((d) => d.orderIndex), [0, 1]);
      expect(days.singleWhere((d) => d.id == 3).orderIndex, 0);
    });

    test('slot label seeds from the legacy day name', () async {
      final days = await db.select(db.programDays).get();
      expect(days.singleWhere((d) => d.id == 1).slotLabel, 'Push AM');
      expect(days.singleWhere((d) => d.id == 4).slotLabel, 'Full Body');
    });

    test('start date is the earliest scheduled date per program', () async {
      final programs = await db.select(db.programs).get();
      expect(programs.singleWhere((p) => p.id == 1).startDateIso, '2026-01-05');
      expect(programs.singleWhere((p) => p.id == 2).startDateIso, '2026-03-06');
    });

    test('exactly one non-archived program becomes active', () async {
      final programs = await db.select(db.programs).get();
      final active = programs.where((p) => p.isActive).toList();
      expect(active, hasLength(1));
      // Program 2 owns the latest date but is archived, so program 1 wins.
      expect(active.single.id, 1);
    });

    test('the new template FKs are enforced, not just declared', () async {
      await db.into(db.workoutTemplates).insert(
        WorkoutTemplatesCompanion.insert(name: 'Push Day'),
      );
      // Valid reference is accepted...
      await (db.update(db.programDays)..where((t) => t.id.equals(1))).write(
        const ProgramDaysCompanion(templateId: Value(1)),
      );
      expect(
        (await (db.select(
          db.programDays,
        )..where((t) => t.id.equals(1))).getSingle()).templateId,
        1,
      );
      // ...a dangling one is not.
      await expectLater(
        (db.update(db.programDays)..where((t) => t.id.equals(2))).write(
          const ProgramDaysCompanion(templateId: Value(9999)),
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
