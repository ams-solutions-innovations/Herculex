import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:herculex/data/local/database.dart';

import 'support/test_database.dart';

/// RB-04 Phase 3: proves `PRAGMA foreign_keys = ON` is actually wired up via
/// `beforeOpen` on a production-shaped [AppDatabase] — as opposed to
/// `test/fk_constraints_test.dart` (Phase 0), which only locks the *declared*
/// schema, and `test/fk_repair_test.dart` (Phase 2), which proves the
/// migration-time repair. None of those tests would fail if `beforeOpen`
/// were silently removed; these do.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PRAGMA foreign_keys reads 1 on a freshly opened database, unasked', () async {
    // Bypasses openTestDatabase() entirely — the point is to prove the
    // pragma is on by construction, not because a test helper asked for it.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });

  test('inserting a child row with a bogus parent id throws', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final sessionId = await db
        .into(db.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));

    expect(
      () => db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: 999999, // no such exercise_catalog row
              orderIndex: 0,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a workout_session cascades to set_entries at the DB level', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final exerciseId = await (db.select(
      db.exerciseCatalog,
    )..limit(1)).getSingle().then((e) => e.id);

    final sessionId = await db
        .into(db.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
    final workoutExerciseId = await db.into(db.workoutExercises).insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );
    await db.into(db.setEntries).insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: workoutExerciseId,
            setIndex: 0,
            weightKg: 60,
            reps: 5,
          ),
        );

    // Deletes the session directly via the raw driver — not through
    // WorkoutsRepository.deleteSession, which already child-deletes itself
    // (Phase 1). The point here is that the database enforces the cascade
    // even when a caller doesn't.
    await db.customStatement(
      'DELETE FROM workout_sessions WHERE id = ?',
      [sessionId],
    );

    final remainingExercises = await (db.select(
      db.workoutExercises,
    )..where((t) => t.sessionId.equals(sessionId))).get();
    final remainingSets = await (db.select(
      db.setEntries,
    )..where((t) => t.workoutExerciseId.equals(workoutExerciseId))).get();
    expect(remainingExercises, isEmpty);
    expect(remainingSets, isEmpty);
  });

  test('deleting a referenced food throws', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final foodId = await db.into(db.foods).insert(
          FoodsCompanion.insert(name: 'Test Food', kcalPer100g: 100),
        );
    await db.into(db.foodEntries).insert(
          FoodEntriesCompanion.insert(
            dateIso: '2026-01-01',
            meal: 'lunch',
            foodId: Value(foodId),
          ),
        );

    expect(
      () => db.customStatement('DELETE FROM foods WHERE id = ?', [foodId]),
      throwsA(isA<SqliteException>()),
    );
  });

  test(
    'PRAGMA foreign_keys is a no-op inside a transaction — why onUpgrade '
    "can't be where it's set",
    () async {
      // onCreate/onUpgrade both run inside drift's migration transaction
      // (this is *the* reason beforeOpen — which runs after that
      // transaction commits — is the only correct place for the pragma;
      // see database.dart's beforeOpen comment and Phase 0's discovery).
      // db.transaction() below re-creates that exact condition: any
      // attempt to flip PRAGMA foreign_keys inside it must not stick,
      // during or after.
      final db = await openTestDatabase();
      addTearDown(db.close);

      final before = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(before.data.values.single, 1, reason: 'ON going in, via beforeOpen');

      await db.transaction(() async {
        await db.customStatement('PRAGMA foreign_keys = OFF');
        final duringTxn = await db
            .customSelect('PRAGMA foreign_keys')
            .getSingle();
        expect(
          duringTxn.data.values.single,
          1,
          reason: 'SQLite silently ignores the pragma write inside a '
              'transaction — the exact reason onUpgrade cannot set it',
        );
      });

      final after = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        after.data.values.single,
        1,
        reason: 'the OFF write never took effect, not even after commit',
      );
    },
  );
}
