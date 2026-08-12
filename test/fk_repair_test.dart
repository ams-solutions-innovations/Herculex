import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/fk_repair.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';

import 'support/test_database.dart';

/// RB-04 Phase 2: `repairForeignKeyViolations` brings a database with
/// pre-existing orphans (possible because `PRAGMA foreign_keys` has never
/// been on in production) to zero `foreign_key_check` violations, with the
/// pragma still off. Every insert below is done against a database opened
/// with `foreignKeys: false`, so SQLite accepts the dangling references —
/// exactly how they could have landed on a real device pre-Phase-3.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('repairForeignKeyViolations', () {
    test('deletes orphans and nulls SET NULL edges, one per class', () async {
      final db = await openTestDatabase(foreignKeys: false);
      addTearDown(db.close);

      final exerciseId = await (db.select(
        db.exerciseCatalog,
      )..limit(1)).getSingle().then((e) => e.id);
      const bogusExerciseId = 999999;
      const bogusGymId = 888888;
      const bogusFoodId = 777777;
      const bogusSessionId = 666666;

      // 1. workout_exercise with a bogus exercise_id (RESTRICT edge).
      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final orphanWeId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: bogusExerciseId,
              orderIndex: 0,
            ),
          );

      // 2. set_entry under a workout_exercise id that doesn't exist
      // (CASCADE edge).
      final orphanSetId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: 555555,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
            ),
          );

      // 3. workout_session with a bogus gym_id (SET NULL edge).
      final orphanGymSessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: DateTime(2026),
              gymId: const Value(bogusGymId),
            ),
          );

      // 4. food_entry with a bogus food_id (RESTRICT edge).
      final orphanEntryId = await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-01-01',
              meal: 'lunch',
              foodId: const Value(bogusFoodId),
            ),
          );

      // 5. template_exercise with a bogus exercise_id (RESTRICT edge).
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'T'));
      final orphanTemplateExerciseId = await db
          .into(db.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: bogusExerciseId,
              orderIndex: 0,
            ),
          );

      // 6. scheduled_workouts pointing at a session that doesn't exist, with
      // status='done' — the sibling-column fix the plan calls out
      // specifically (SET NULL edge + a status repair that isn't the bare
      // FK action).
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'P'));
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Day 1',
            ),
          );
      final orphanScheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-01-01',
              programDayId: dayId,
              completedSessionId: const Value(bogusSessionId),
              status: const Value(ScheduleStatus.done),
            ),
          );

      expect(await foreignKeyViolations(db), isNotEmpty);

      final report = await repairForeignKeyViolations(db);

      expectNoForeignKeyViolations(await foreignKeyViolations(db));
      expect(report.residualViolations, 0);

      // 1. orphan workout_exercise deleted.
      expect(
        await (db.select(
          db.workoutExercises,
        )..where((t) => t.id.equals(orphanWeId))).getSingleOrNull(),
        isNull,
      );
      expect(report.deleted['workout_exercises'], greaterThanOrEqualTo(1));

      // 2. orphan set_entry deleted.
      expect(
        await (db.select(
          db.setEntries,
        )..where((t) => t.id.equals(orphanSetId))).getSingleOrNull(),
        isNull,
      );
      expect(report.deleted['set_entries'], greaterThanOrEqualTo(1));

      // 3. gym_id nulled, session row kept.
      final gymSession = await (db.select(
        db.workoutSessions,
      )..where((t) => t.id.equals(orphanGymSessionId))).getSingle();
      expect(gymSession.gymId, isNull);
      expect(report.nulled['workout_sessions.gym_id'], greaterThanOrEqualTo(1));

      // 4. orphan food_entry deleted.
      expect(
        await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(orphanEntryId))).getSingleOrNull(),
        isNull,
      );
      expect(report.deleted['food_entries'], greaterThanOrEqualTo(1));

      // 5. orphan template_exercise deleted.
      expect(
        await (db.select(
          db.templateExercises,
        )..where((t) => t.id.equals(orphanTemplateExerciseId))).getSingleOrNull(),
        isNull,
      );
      expect(report.deleted['template_exercises'], greaterThanOrEqualTo(1));

      // 6. completed_session_id nulled and status reset off 'done'.
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(orphanScheduleId))).getSingle();
      expect(schedule.completedSessionId, isNull);
      expect(schedule.status, ScheduleStatus.planned);
      expect(
        report.nulled['scheduled_workouts.completed_session_id'],
        greaterThanOrEqualTo(1),
      );

      // Real, non-orphan data (the catalog exercise, the untouched program
      // tree) survives untouched.
      expect(
        await (db.select(
          db.exerciseCatalog,
        )..where((t) => t.id.equals(exerciseId))).getSingleOrNull(),
        isNotNull,
      );
    });

    test('is idempotent — a second run repairs nothing further', () async {
      final db = await openTestDatabase(foreignKeys: false);
      addTearDown(db.close);
      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: 999999,
              orderIndex: 0,
            ),
          );

      final first = await repairForeignKeyViolations(db);
      expect(first.deleted['workout_exercises'], 1);

      final second = await repairForeignKeyViolations(db);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
      expect(second.residualViolations, 0);
      for (final count in second.nulled.values) {
        expect(count, 0);
      }
      for (final count in second.deleted.values) {
        expect(count, 0);
      }
    });

    test('is a no-op on a clean database', () async {
      final db = await openTestDatabase(foreignKeys: false);
      addTearDown(db.close);

      final report = await repairForeignKeyViolations(db);

      expect(report.residualViolations, 0);
      for (final count in report.nulled.values) {
        expect(count, 0);
      }
      for (final count in report.deleted.values) {
        expect(count, 0);
      }
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });

  group('v22 -> v23 migration', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('herculex_v23_');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('reaches user_version 24 and repairs a planted orphan', () async {
      // The v22 table shapes are byte-identical to v23's — Phase 2 adds no
      // columns, only a data repair and indexes — so building a real,
      // fully-shaped database via the normal onCreate path and then
      // rewinding its stamped user_version to 22 is a faithful "v22-shaped
      // file DB", without hand-transcribing ~30 tables of DDL the way
      // schema_v21_test.dart's fixture does for its narrower slice.
      var db = AppDatabase.forTesting(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').getSingle(); // force onCreate
      // RB-04 Phase 3: beforeOpen now turns real FK enforcement on for every
      // database, including this one. Planting an orphan below simulates
      // data that could only exist pre-Phase-3, so enforcement has to be
      // turned back off first — otherwise the insert itself throws instead
      // of landing as an orphan for the migration to repair.
      await db.customStatement('PRAGMA foreign_keys = OFF');

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: 999999,
              orderIndex: 0,
            ),
          );
      await db.customStatement('PRAGMA user_version = 22');
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').getSingle(); // force onUpgrade
      addTearDown(db.close);

      final versionRow = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(versionRow.data.values.first, 24);

      expectNoForeignKeyViolations(await foreignKeyViolations(db));
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.workoutSessions).get(), hasLength(1));
    });
  });
}
