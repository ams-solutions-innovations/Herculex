import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/workout_energy_estimator.dart';

/// Headline numbers for one finished session, shown on the finish screen and
/// in the shareable card.
class SessionSummary {
  final int sessionId;
  final String name;
  final DateTime startedAt;
  final Duration duration;

  final int totalSets;
  final int totalReps;

  /// Tonnage in kg, using effective load (bands, chains, bodyweight).
  final double tonnageKg;

  final int exerciseCount;

  /// Muscle groups trained, heaviest first — at most a handful, for chips.
  final List<String> muscleGroups;

  /// Unlocked records and achievements for this session (for share card & review).
  final List<InAppNotificationItem> achievements;

  /// Photo path on local device, if attached.
  final String? photoPath;

  /// Conservative active energy above rest (kcal), or a saved import value.
  final int caloriesBurned;

  /// Tonnage of the most recent earlier session with the same name, for
  /// "+6% vs last Push A". Null when this is the first one.
  final double? previousTonnageKg;

  const SessionSummary({
    required this.sessionId,
    required this.name,
    required this.startedAt,
    required this.duration,
    required this.totalSets,
    required this.totalReps,
    required this.tonnageKg,
    required this.exerciseCount,
    required this.muscleGroups,
    this.achievements = const [],
    this.photoPath,
    this.caloriesBurned = 0,
    this.previousTonnageKg,
  });

  /// Reduces a loaded [snapshot] to just [sessionId].
  static SessionSummary fromSnapshot({
    required TrainingSnapshot snapshot,
    required int sessionId,
    required String name,
    required DateTime startedAt,
    required DateTime? endedAt,
    List<InAppNotificationItem> achievements = const [],
    String? photoPath,
    int? savedCalories,
    double? userWeightKg,
    WorkoutEnergyEstimate? energyEstimate,
  }) {
    final sets = [
      for (final rs in snapshot.sets)
        if (rs.session.id == sessionId) rs,
    ];

    final musclesByExercise = <int, List<String>>{};
    for (final m in snapshot.exerciseMuscles) {
      if (m.role != 'primary') continue;
      musclesByExercise
          .putIfAbsent(m.exerciseId, () => [])
          .add(MuscleRecoveryV3.alias[m.muscle] ?? m.muscle);
    }

    var reps = 0;
    var tonnage = 0.0;
    final exerciseIds = <int>{};
    final muscleSets = <String, int>{};

    for (final rs in sets) {
      reps += rs.countedReps;
      tonnage += rs.tonnageKg;
      exerciseIds.add(rs.exercise.id);

      final muscles =
          musclesByExercise[rs.exercise.id] ??
          [
            MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
                rs.exercise.primaryMuscle,
          ];
      for (final m in muscles) {
        muscleSets[m] = (muscleSets[m] ?? 0) + 1;
      }
    }

    final duration = (endedAt ?? startedAt).difference(startedAt);

    int finalCalories;
    if (savedCalories != null && savedCalories >= 0) {
      finalCalories = savedCalories;
    } else {
      finalCalories =
          (energyEstimate ??
                  WorkoutEnergyEstimator.estimate(
                    snapshot: snapshot,
                    sessionId: sessionId,
                    startedAt: startedAt,
                    endedAt: endedAt ?? startedAt,
                    userWeightKg: userWeightKg,
                  ))
              .activeKcal;
    }

    // The same workout last time: tonnage per earlier session of this name,
    // kept for the newest one.
    final earlier = <int, double>{};
    int? previousId;
    DateTime? previousAt;
    for (final rs in snapshot.sets) {
      final s = rs.session;
      if (s.id == sessionId || !s.startedAt.isBefore(startedAt)) continue;
      final sName = (s.name?.trim().isNotEmpty ?? false)
          ? s.name!.trim()
          : 'Workout';
      if (sName != name) continue;
      earlier[s.id] = (earlier[s.id] ?? 0) + rs.tonnageKg;
      if (previousAt == null || s.startedAt.isAfter(previousAt)) {
        previousAt = s.startedAt;
        previousId = s.id;
      }
    }

    final ranked = muscleSets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SessionSummary(
      sessionId: sessionId,
      name: name,
      startedAt: startedAt,
      duration: duration,
      totalSets: sets.length,
      totalReps: reps,
      tonnageKg: tonnage,
      exerciseCount: exerciseIds.length,
      muscleGroups: [for (final e in ranked.take(4)) e.key],
      achievements: achievements,
      photoPath: photoPath,
      caloriesBurned: finalCalories,
      previousTonnageKg: previousId == null ? null : earlier[previousId],
    );
  }

  /// `1h 12m` / `48m` — never a bare `0h`.
  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Tonnes above 1 t, kilograms below, matching the dashboard's formatting.
  /// Non-finite guard for the same reason as `WeightFormat.formatTonnage`:
  /// `round()` throws on NaN, and this is read from a `build()`.
  String get tonnageLabel => !tonnageKg.isFinite
      ? '0 kg'
      : tonnageKg >= 1000
      ? '${(tonnageKg / 1000).toStringAsFixed(1)} t'
      : '${tonnageKg.round()} kg';

  /// Tonnage change against [previousTonnageKg] as a fraction (0.06 = +6%),
  /// or null when there is nothing comparable.
  double? get tonnageChange {
    final before = previousTonnageKg;
    if (before == null || before <= 0 || !tonnageKg.isFinite) return null;
    return tonnageKg / before - 1;
  }

  /// Format calories burned.
  String get caloriesLabel => '$caloriesBurned kcal';
}
