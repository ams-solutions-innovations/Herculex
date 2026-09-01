import 'package:drift/drift.dart';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';

class ExerciseProgressionsRepository {
  final AppDatabase _db;
  ExerciseProgressionsRepository(this._db);

  Future<ExerciseProgressionData?> forExercise(int exerciseId) {
    return (_db.select(
      _db.exerciseProgressions,
    )..where((t) => t.exerciseId.equals(exerciseId))).getSingleOrNull();
  }

  Stream<List<ExerciseProgressionData>> watchAll() {
    return _db.select(_db.exerciseProgressions).watch();
  }

  Future<void> upsert(
    int exerciseId, {
    required ProgressionGoal goal,
    required double weeklyIncreasePct,
    required bool enabled,
  }) async {
    await _db
        .into(_db.exerciseProgressions)
        .insert(
          ExerciseProgressionsCompanion.insert(
            exerciseId: exerciseId,
            goal: Value(goal.name),
            weeklyIncreasePct: Value(weeklyIncreasePct),
            enabled: Value(enabled),
          ),
          onConflict: DoUpdate(
            (old) => ExerciseProgressionsCompanion.custom(
              goal: Constant(goal.name),
              weeklyIncreasePct: Constant(weeklyIncreasePct),
              enabled: Constant(enabled),
            ),
            target: [_db.exerciseProgressions.exerciseId],
          ),
        );
  }

  Future<void> delete(int exerciseId) async {
    await (_db.delete(
      _db.exerciseProgressions,
    )..where((t) => t.exerciseId.equals(exerciseId))).go();
  }
}
