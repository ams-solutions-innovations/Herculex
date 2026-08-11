import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late WorkoutsRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = WorkoutsRepository(db, const SystemClock());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createExercise(String name) {
    return db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'Chest',
            equipment: 'Dumbbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
  }

  test(
    'active notification target reads the latest set values from the db',
    () async {
      final sessionId = await repo.startSession();
      final exerciseId = await createExercise('Incline Press');
      final workoutExerciseId = await repo.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: exerciseId,
      );
      final set =
          await (db.select(db.setEntries)
                ..where((t) => t.workoutExerciseId.equals(workoutExerciseId)))
              .getSingle();

      await repo.updateSet(setId: set.id, reps: 9, weightKg: 82.5);

      final target = await repo.activeNotificationTargetForSession(sessionId);

      expect(target?.exerciseName, 'Incline Press');
      expect(target?.set.id, set.id);
      expect(target?.set.reps, 9);
      expect(target?.set.weightKg, 82.5);
    },
  );

  test(
    'active notification target advances after completing the current set',
    () async {
      final sessionId = await repo.startSession();
      final exerciseId = await createExercise('Incline Press');
      final workoutExerciseId = await repo.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: exerciseId,
      );
      await repo.addSet(
        workoutExerciseId: workoutExerciseId,
        weightKg: 80,
        reps: 8,
      );
      final sets =
          await (db.select(db.setEntries)
                ..where((t) => t.workoutExerciseId.equals(workoutExerciseId))
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();
      final firstSet = sets[0];
      final secondSet = sets[1];

      await repo.updateSet(setId: firstSet.id, isCompleted: true);

      final target = await repo.activeNotificationTargetForSession(sessionId);

      expect(target?.set.id, secondSet.id);
      expect(target?.set.isCompleted, isFalse);
    },
  );
}
