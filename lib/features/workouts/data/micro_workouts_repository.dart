import 'package:drift/drift.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:uuid/uuid.dart';

/// A micro workout with today's completion count and optional exercise metadata resolved.
class MicroWorkoutStatus {
  final MicroWorkoutData microWorkout;
  final int completedToday;
  final ExerciseCatalogData? exercise;

  const MicroWorkoutStatus(
    this.microWorkout,
    this.completedToday, {
    this.exercise,
  });

  bool get doneForToday => completedToday >= microWorkout.timesPerDay;

  double get progress => microWorkout.timesPerDay > 0
      ? (completedToday / microWorkout.timesPerDay).clamp(0.0, 1.0)
      : 0.0;

  int get remainingToday => (microWorkout.timesPerDay - completedToday).clamp(
    0,
    microWorkout.timesPerDay,
  );

  int get repsCompletedToday => completedToday * microWorkout.targetReps;

  int get totalTargetRepsToday =>
      microWorkout.timesPerDay * microWorkout.targetReps;
}

/// A logged completion session for a micro workout.
class MicroWorkoutLogEntry {
  final int sessionId;
  final int microWorkoutId;
  final String microWorkoutName;
  final String exerciseName;
  final int reps;
  final double weightKg;
  final DateTime completedAt;

  const MicroWorkoutLogEntry({
    required this.sessionId,
    required this.microWorkoutId,
    required this.microWorkoutName,
    required this.exerciseName,
    required this.reps,
    required this.weightKg,
    required this.completedAt,
  });
}

/// 7-day consistency and streak stats for micro workouts.
class MicroWorkoutWeeklyStats {
  /// Map of Date (at midnight) -> count of completed micro workout sets.
  final Map<DateTime, int> dailySets;

  /// Total reps logged across micro workouts in the last 7 days.
  final int totalRepsWeek;

  /// Consecutive active streak in days.
  final int streakDays;

  const MicroWorkoutWeeklyStats({
    required this.dailySets,
    required this.totalRepsWeek,
    required this.streakDays,
  });
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

  Stream<List<MicroWorkoutData>> watchAll() {
    return (_db.select(
      _db.microWorkouts,
    )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).watch();
  }

  Future<int> create({
    required String name,
    required int exerciseId,
    required int targetReps,
    int timesPerDay = 1,
  }) {
    return _db
        .into(_db.microWorkouts)
        .insert(
          MicroWorkoutsCompanion.insert(
            name: name,
            exerciseId: exerciseId,
            targetReps: targetReps,
            timesPerDay: Value(timesPerDay),
          ),
        );
  }

  Future<void> update({
    required int id,
    String? name,
    int? exerciseId,
    int? targetReps,
    int? timesPerDay,
    bool? active,
  }) async {
    await (_db.update(_db.microWorkouts)..where((t) => t.id.equals(id))).write(
      MicroWorkoutsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        exerciseId: exerciseId != null
            ? Value(exerciseId)
            : const Value.absent(),
        targetReps: targetReps != null
            ? Value(targetReps)
            : const Value.absent(),
        timesPerDay: timesPerDay != null
            ? Value(timesPerDay)
            : const Value.absent(),
        active: active != null ? Value(active) : const Value.absent(),
      ),
    );
  }

  Future<void> setActive(int id, bool active) async {
    await (_db.update(_db.microWorkouts)..where((t) => t.id.equals(id))).write(
      MicroWorkoutsCompanion(active: Value(active)),
    );
  }

  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.workoutSessions)
            ..where((t) => t.microWorkoutId.equals(id)))
          .write(const WorkoutSessionsCompanion(microWorkoutId: Value(null)));
      await (_db.delete(_db.microWorkouts)..where((t) => t.id.equals(id))).go();
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
      final sessionId = await _db
          .into(_db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: now,
              endedAt: Value(now),
              notes: Value('Micro: ${micro.name}'),
              microWorkoutId: Value(micro.id),
              sessionUuid: Value(const Uuid().v4()),
            ),
          );
      final weId = await _db
          .into(_db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: micro.exerciseId,
              orderIndex: 0,
            ),
          );
      await _db
          .into(_db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 0,
              weightKg: weightKg,
              reps: reps ?? micro.targetReps,
              isCompleted: const Value(true),
              completedAt: Value(now),
              bodyweightKg: Value(bodyweightKg),
            ),
          );
      return sessionId;
    });
  }

  /// Undoes the most recent completion logged today for [microWorkoutId].
  Future<bool> undoLastCompletion(int microWorkoutId) async {
    final now = _clock.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final sessions =
        await (_db.select(_db.workoutSessions)
              ..where(
                (t) =>
                    t.microWorkoutId.equals(microWorkoutId) &
                    t.startedAt.isBiggerOrEqualValue(dayStart) &
                    t.startedAt.isSmallerThanValue(dayEnd),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .get();

    if (sessions.isEmpty) return false;
    await deleteSession(sessions.first.id);
    return true;
  }

  /// Deletes a logged workout session along with its workoutExercises and setEntries.
  Future<void> deleteSession(int sessionId) async {
    await _db.transaction(() async {
      final exercises = await (_db.select(
        _db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      for (final e in exercises) {
        await (_db.delete(
          _db.setEntries,
        )..where((t) => t.workoutExerciseId.equals(e.id))).go();
      }
      await (_db.delete(
        _db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).go();
      await (_db.delete(
        _db.workoutSessions,
      )..where((t) => t.id.equals(sessionId))).go();
    });
  }

  /// Completion counts for [dayStart]..+24h, keyed by micro workout id.
  Future<Map<int, int>> completionsOn(DateTime dayStart) async {
    final from = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final to = from.add(const Duration(days: 1));
    final rows =
        await (_db.select(_db.workoutSessions)..where(
              (t) =>
                  t.microWorkoutId.isNotNull() &
                  t.startedAt.isBiggerOrEqualValue(from) &
                  t.startedAt.isSmallerThanValue(to),
            ))
            .get();
    final counts = <int, int>{};
    for (final s in rows) {
      counts[s.microWorkoutId!] = (counts[s.microWorkoutId!] ?? 0) + 1;
    }
    return counts;
  }

  /// Active micro workouts with today's progress and exercise catalog details.
  Stream<List<MicroWorkoutStatus>> watchTodayStatus() {
    return watchActive().asyncMap((micros) async {
      final counts = await completionsOn(_clock.now());
      final result = <MicroWorkoutStatus>[];
      for (final m in micros) {
        final ex = await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(m.exerciseId))).getSingleOrNull();
        result.add(MicroWorkoutStatus(m, counts[m.id] ?? 0, exercise: ex));
      }
      return result;
    });
  }

  /// All micro workouts (active and paused) with today's progress.
  Stream<List<MicroWorkoutStatus>> watchAllStatus() {
    return watchAll().asyncMap((micros) async {
      final counts = await completionsOn(_clock.now());
      final result = <MicroWorkoutStatus>[];
      for (final m in micros) {
        final ex = await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(m.exerciseId))).getSingleOrNull();
        result.add(MicroWorkoutStatus(m, counts[m.id] ?? 0, exercise: ex));
      }
      return result;
    });
  }

  /// Watch logged sessions completed today for micro workouts.
  Stream<List<MicroWorkoutLogEntry>> watchTodayLogs() {
    final now = _clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return (_db.select(_db.workoutSessions)
          ..where(
            (t) =>
                t.microWorkoutId.isNotNull() &
                t.startedAt.isBiggerOrEqualValue(today) &
                t.startedAt.isSmallerThanValue(tomorrow),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ]))
        .watch()
        .asyncMap((sessions) async {
          if (sessions.isEmpty) return <MicroWorkoutLogEntry>[];

          final list = <MicroWorkoutLogEntry>[];
          final microMap = <int, MicroWorkoutData>{};
          final exerciseMap = <int, ExerciseCatalogData>{};

          for (final s in sessions) {
            final microId = s.microWorkoutId;
            if (microId == null) continue;

            if (!microMap.containsKey(microId)) {
              final m = await (_db.select(
                _db.microWorkouts,
              )..where((t) => t.id.equals(microId))).getSingleOrNull();
              if (m != null) microMap[microId] = m;
            }
            final micro = microMap[microId];
            if (micro == null) continue;

            if (!exerciseMap.containsKey(micro.exerciseId)) {
              final ex = await (_db.select(
                _db.exerciseCatalog,
              )..where((t) => t.id.equals(micro.exerciseId))).getSingleOrNull();
              if (ex != null) exerciseMap[micro.exerciseId] = ex;
            }
            final exercise = exerciseMap[micro.exerciseId];

            final we = await (_db.select(
              _db.workoutExercises,
            )..where((t) => t.sessionId.equals(s.id))).getSingleOrNull();
            int reps = micro.targetReps;
            double weightKg = 0;
            if (we != null) {
              final set =
                  await (_db.select(_db.setEntries)
                        ..where((t) => t.workoutExerciseId.equals(we.id)))
                      .getSingleOrNull();
              if (set != null) {
                reps = set.reps;
                weightKg = set.weightKg;
              }
            }

            list.add(
              MicroWorkoutLogEntry(
                sessionId: s.id,
                microWorkoutId: micro.id,
                microWorkoutName: micro.name,
                exerciseName: exercise?.name ?? micro.name,
                reps: reps,
                weightKg: weightKg,
                completedAt: s.startedAt,
              ),
            );
          }
          return list;
        });
  }

  /// Watch 7-day consistency and streak stats.
  Stream<MicroWorkoutWeeklyStats> watchWeeklyStats() {
    final now = _clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));

    return (_db.select(_db.workoutSessions)
          ..where(
            (t) =>
                t.microWorkoutId.isNotNull() &
                t.startedAt.isBiggerOrEqualValue(weekStart),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt)]))
        .watch()
        .asyncMap((sessions) async {
          final dailySets = <DateTime, int>{};
          for (int i = 0; i < 7; i++) {
            final day = weekStart.add(Duration(days: i));
            dailySets[DateTime(day.year, day.month, day.day)] = 0;
          }

          int totalReps = 0;
          final sessionIds = sessions.map((s) => s.id).toList();
          if (sessionIds.isNotEmpty) {
            final weRows = await (_db.select(
              _db.workoutExercises,
            )..where((t) => t.sessionId.isIn(sessionIds))).get();
            final weIds = weRows.map((e) => e.id).toList();
            if (weIds.isNotEmpty) {
              final sets = await (_db.select(
                _db.setEntries,
              )..where((t) => t.workoutExerciseId.isIn(weIds))).get();
              for (final set in sets) {
                totalReps += set.reps;
              }
            }
          }

          for (final s in sessions) {
            final day = DateTime(
              s.startedAt.year,
              s.startedAt.month,
              s.startedAt.day,
            );
            if (dailySets.containsKey(day)) {
              dailySets[day] = (dailySets[day] ?? 0) + 1;
            }
          }

          // Compute streak
          int streak = 0;
          var checkDay = today;
          if ((dailySets[checkDay] ?? 0) > 0) {
            streak++;
            checkDay = checkDay.subtract(const Duration(days: 1));
          } else {
            final yesterday = checkDay.subtract(const Duration(days: 1));
            if ((dailySets[yesterday] ?? 0) > 0) {
              checkDay = yesterday;
            }
          }

          while (true) {
            if ((dailySets[checkDay] ?? 0) > 0) {
              if (checkDay != today) streak++;
              checkDay = checkDay.subtract(const Duration(days: 1));
            } else {
              break;
            }
          }

          return MicroWorkoutWeeklyStats(
            dailySets: dailySets,
            totalRepsWeek: totalReps,
            streakDays: streak,
          );
        });
  }
}
