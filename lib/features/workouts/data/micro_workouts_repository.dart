import 'package:drift/drift.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';

/// A micro workout with today's completion count resolved.
class MicroWorkoutStatus {
  final MicroWorkoutData microWorkout;
  final int completedToday;
  const MicroWorkoutStatus(this.microWorkout, this.completedToday);

  bool get doneForToday => completedToday >= microWorkout.timesPerDay;
}

/// Micro workouts (V2 §20): small scheduled daily tasks ("50 pushups every
/// 3 hours"). Completions are written as real one-exercise workout sessions,
/// so tonnage, recovery, CNS, and analytics pick them up with zero special
/// cases.
class MicroWorkoutsRepository {
  final AppDatabase _db;
  final Clock _clock;

  MicroWorkoutsRepository(this._db, this._clock);

  Stream<List<MicroWorkoutData>> watchActive() {
    return (_db.select(_db.microWorkouts)
          ..where((t) => t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<int> create({
    required String name,
    required int exerciseId,
    required int targetReps,
    int timesPerDay = 1,
  }) {
    return _db.into(_db.microWorkouts).insert(MicroWorkoutsCompanion.insert(
          name: name,
          exerciseId: exerciseId,
          targetReps: targetReps,
          timesPerDay: Value(timesPerDay),
        ));
  }

  Future<void> setActive(int id, bool active) async {
    await (_db.update(_db.microWorkouts)..where((t) => t.id.equals(id)))
        .write(MicroWorkoutsCompanion(active: Value(active)));
  }

  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.workoutSessions)
            ..where((t) => t.microWorkoutId.equals(id)))
          .write(const WorkoutSessionsCompanion(microWorkoutId: Value(null)));
      await (_db.delete(_db.microWorkouts)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  /// Logs one completion: a closed mini-session containing a single completed
  /// set. [reps] defaults to the prescribed target; [weightKg] covers weighted
  /// variants (e.g. weighted-vest pushups).
  Future<int> logCompletion(
    MicroWorkoutData micro, {
    int? reps,
    double weightKg = 0,
    double? bodyweightKg,
  }) async {
    final now = _clock.now();
    return _db.transaction(() async {
      final sessionId = await _db.into(_db.workoutSessions).insert(
            WorkoutSessionsCompanion.insert(
              startedAt: now,
              endedAt: Value(now),
              notes: Value('Micro: ${micro.name}'),
              microWorkoutId: Value(micro.id),
            ),
          );
      final weId = await _db.into(_db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: micro.exerciseId,
              orderIndex: 0,
            ),
          );
      await _db.into(_db.setEntries).insert(SetEntriesCompanion.insert(
            workoutExerciseId: weId,
            setIndex: 0,
            weightKg: weightKg,
            reps: reps ?? micro.targetReps,
            isCompleted: const Value(true),
            completedAt: Value(now),
            bodyweightKg: Value(bodyweightKg),
          ));
      return sessionId;
    });
  }

  /// Completion counts for [dayStart]..+24h, keyed by micro workout id.
  Future<Map<int, int>> completionsOn(DateTime dayStart) async {
    final from = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final to = from.add(const Duration(days: 1));
    final rows = await (_db.select(_db.workoutSessions)
          ..where((t) =>
              t.microWorkoutId.isNotNull() &
              t.startedAt.isBiggerOrEqualValue(from) &
              t.startedAt.isSmallerThanValue(to)))
        .get();
    final counts = <int, int>{};
    for (final s in rows) {
      counts[s.microWorkoutId!] = (counts[s.microWorkoutId!] ?? 0) + 1;
    }
    return counts;
  }

  /// Active micro workouts with today's progress, for the checklist UI.
  Stream<List<MicroWorkoutStatus>> watchTodayStatus() {
    return watchActive().asyncMap((micros) async {
      final counts = await completionsOn(_clock.now());
      return [
        for (final m in micros) MicroWorkoutStatus(m, counts[m.id] ?? 0),
      ];
    });
  }
}
