import 'dart:math';

import 'package:health/health.dart';
import '../../../data/local/database.dart';
import '../../health/domain/external_workout_cns_mapper.dart';

class CnsFatigueResult {
  /// Accumulated CNS load, 0.0 (fresh) to 1.0 (maximally taxed).
  final double load;

  const CnsFatigueResult(this.load);

  double get readiness => (1.0 - load).clamp(0.0, 1.0);

  bool get isExcessive => load >= 0.7;

  String get status {
    if (load < 0.4) return 'FRESH';
    if (load < 0.7) return 'MODERATE';
    return 'HIGH';
  }
}

/// Rolling central-nervous-system fatigue accumulator. Each completed working
/// set adds load scaled by the exercise's [ExerciseCatalogData.cnsScore]
/// (1–10), decayed over a longer half-life than peripheral muscle fatigue
/// (CNS recovers more slowly).
class CnsFatigue {
  static const _perSetBase = 0.08;
  static const _windowHours = 96;

  static CnsFatigueResult compute({
    required List<SetEntryData> sets,
    required List<WorkoutExerciseData> workoutExercises,
    required List<ExerciseCatalogData> catalog,
    List<HealthDataPoint> externalWorkouts = const [],
    required DateTime asOf,
    double halfLifeHours = 36,
  }) {
    final exerciseMap = {for (final ex in catalog) ex.id: ex};
    final weMap = {for (final we in workoutExercises) we.id: we};

    var load = 0.0;
    for (final set in sets) {
      if (!set.isCompleted || set.completedAt == null || set.isWarmup) continue;
      final we = weMap[set.workoutExerciseId];
      if (we == null) continue;
      final ex = exerciseMap[we.exerciseId];
      if (ex == null) continue;

      final hours = asOf.difference(set.completedAt!).inHours;
      if (hours > _windowHours) continue;

      final intensity = ex.cnsScore / 10.0; // 0.1 – 1.0
      final rpe = set.rpeX10 != null ? set.rpeX10! / 10.0 : 7.0;
      final rpeFactor = rpe >= 8 ? 1.3 : 1.0;
      final decay = exp(-hours / halfLifeHours);
      load += _perSetBase * intensity * rpeFactor * decay;
    }

    // Process external workouts
    for (final workout in externalWorkouts) {
      if (workout.value is! WorkoutHealthValue) continue;
      final wv = workout.value as WorkoutHealthValue;
      
      final hours = asOf.difference(workout.dateTo).inHours;
      if (hours > _windowHours) continue;

      final impact = ExternalWorkoutCnsMapper.getImpactFor(wv.workoutActivityType);
      
      // Calculate equivalent sets based on duration. E.g. 1 hour = ~20 sets equivalent load for high intensity.
      final durationMinutes = workout.dateTo.difference(workout.dateFrom).inMinutes;
      final equivalentSets = (durationMinutes / 60.0) * 15.0; // 15 sets per hour
      
      final rpeFactor = 1.0; // Assume moderate intensity for external workouts
      final decay = exp(-hours / halfLifeHours);
      
      // We apply the base CNS score of the workout type
      load += _perSetBase * equivalentSets * impact.baseCnsScore * rpeFactor * decay;
    }

    return CnsFatigueResult(load.clamp(0.0, 1.0));
  }
}
