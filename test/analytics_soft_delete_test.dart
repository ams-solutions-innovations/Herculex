import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/data/analytics_repository.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

import 'support/test_database.dart';

/// ANLY-03 / 09-CONTEXT.md D-04 acceptance gate: proves a soft-deleted set
/// is excluded from analytics reads, not just asserted by inspection. If the
/// `deletedAt.isNull()` filtering added in Plan 09-01 to
/// `training_snapshot.dart` / `analytics_repository.dart` is ever removed,
/// these tests fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Row id of any exercise from the seeded catalog.
  Future<int> anyExerciseId(AppDatabase db) async {
    final row = await (db.select(db.exerciseCatalog)..limit(1)).getSingle();
    return row.id;
  }

  group('analytics excludes soft-deleted sets', () {
    test('TrainingSnapshot excludes a soft-deleted set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
              isCompleted: const Value(true),
            ),
          );

      final before = await TrainingSnapshot.load(db);
      expect(before.sets, hasLength(1));
      expect(before.sets.single.set.id, setId);

      await (db.update(db.setEntries)..where((t) => t.id.equals(setId)))
          .write(SetEntriesCompanion(deletedAt: Value(DateTime.now())));

      final after = await TrainingSnapshot.load(db);
      expect(after.sets, isEmpty);
    });

    test('weeklyTonnage excludes a soft-deleted set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(startedAt: DateTime.now()),
          );
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
              isCompleted: const Value(true),
            ),
          );

      final repo = AnalyticsRepository(db);
      final before = await repo.weeklyTonnage();
      expect(before.last.tonnageKg, 300);

      await (db.update(db.setEntries)..where((t) => t.id.equals(setId)))
          .write(SetEntriesCompanion(deletedAt: Value(DateTime.now())));

      final after = await repo.weeklyTonnage();
      expect(after.last.tonnageKg, 0);
    });

    test('topOneRms excludes a soft-deleted set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final exerciseId = await anyExerciseId(db);

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026)));
      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      final setId = await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: 60,
              reps: 5,
              isCompleted: const Value(true),
            ),
          );

      final repo = AnalyticsRepository(db);
      final before = await repo.topOneRms();
      expect(before.map((p) => p.exerciseId), contains(exerciseId));

      await (db.update(db.setEntries)..where((t) => t.id.equals(setId)))
          .write(SetEntriesCompanion(deletedAt: Value(DateTime.now())));

      final after = await repo.topOneRms();
      expect(after.map((p) => p.exerciseId), isNot(contains(exerciseId)));
    });
  });
}
