import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../../workouts/domain/one_rep_max.dart';

class WeeklyTonnage {
  /// First day (Mon) of the week.
  final DateTime weekStart;
  final double tonnageKg;
  const WeeklyTonnage(this.weekStart, this.tonnageKg);
}

class OneRmProjection {
  final int exerciseId;
  final String exerciseName;
  final double estimatedOneRmKg;
  const OneRmProjection({
    required this.exerciseId,
    required this.exerciseName,
    required this.estimatedOneRmKg,
  });
}

/// All read-only analytics queries over the workout tables.
class AnalyticsRepository {
  final AppDatabase _db;
  AnalyticsRepository(this._db);

  /// Total kg moved (weight × reps), grouped by ISO week, last [weeks] weeks.
  Future<List<WeeklyTonnage>> weeklyTonnage({int weeks = 12}) async {
    final now = DateTime.now();
    final startOfThisWeek = _weekStart(now);
    final from = startOfThisWeek.subtract(Duration(days: 7 * (weeks - 1)));

    final rows = await (_db.select(_db.setEntries).join([
      innerJoin(
        _db.workoutExercises,
        _db.workoutExercises.id.equalsExp(_db.setEntries.workoutExerciseId),
      ),
      innerJoin(
        _db.workoutSessions,
        _db.workoutSessions.id.equalsExp(_db.workoutExercises.sessionId),
      ),
    ])
          ..where(_db.setEntries.isCompleted.equals(true) &
              _db.setEntries.isWarmup.equals(false) &
              _db.workoutSessions.startedAt.isBiggerOrEqualValue(from) &
              _db.setEntries.deletedAt.isNull() &
              _db.workoutExercises.deletedAt.isNull() &
              _db.workoutSessions.deletedAt.isNull()))
        .get();

    final buckets = <DateTime, double>{
      for (var i = 0; i < weeks; i++)
        startOfThisWeek.subtract(Duration(days: 7 * (weeks - 1 - i))): 0.0,
    };

    for (final r in rows) {
      final set = r.readTable(_db.setEntries);
      final session = r.readTable(_db.workoutSessions);
      final ws = _weekStart(session.startedAt);
      buckets[ws] = (buckets[ws] ?? 0) + set.weightKg * set.reps;
    }

    final sorted = buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => WeeklyTonnage(e.key, e.value)).toList();
  }

  /// Top-N estimated 1RMs across all logged exercises (best working set per exercise).
  Future<List<OneRmProjection>> topOneRms({int limit = 5}) async {
    final rows = await (_db.select(_db.setEntries).join([
      innerJoin(
        _db.workoutExercises,
        _db.workoutExercises.id.equalsExp(_db.setEntries.workoutExerciseId),
      ),
      innerJoin(
        _db.exerciseCatalog,
        _db.exerciseCatalog.id.equalsExp(_db.workoutExercises.exerciseId),
      ),
    ])
          ..where(_db.setEntries.isCompleted.equals(true) &
              _db.setEntries.isWarmup.equals(false) &
              _db.setEntries.deletedAt.isNull() &
              _db.workoutExercises.deletedAt.isNull() &
              _db.exerciseCatalog.deletedAt.isNull()))
        .get();

    final best = <int, OneRmProjection>{};
    for (final r in rows) {
      final set = r.readTable(_db.setEntries);
      final ex = r.readTable(_db.exerciseCatalog);
      final est = OneRepMax.estimate(weightKg: set.weightKg, reps: set.reps);
      if (est == null) continue;
      final existing = best[ex.id];
      if (existing == null || est > existing.estimatedOneRmKg) {
        best[ex.id] = OneRmProjection(
          exerciseId: ex.id,
          exerciseName: ex.name,
          estimatedOneRmKg: est,
        );
      }
    }

    final sorted = best.values.toList()
      ..sort((a, b) => b.estimatedOneRmKg.compareTo(a.estimatedOneRmKg));
    return sorted.take(limit).toList();
  }

  DateTime _weekStart(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final delta = local.weekday - DateTime.monday;
    return local.subtract(Duration(days: delta));
  }
}
