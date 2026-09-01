import 'package:health/health.dart';

class CnsImpact {
  final double baseCnsScore; // 0.1 to 1.0
  final Map<String, double>
  muscleInvolvement; // Role weight per muscle (0.0 to 1.0)

  const CnsImpact(this.baseCnsScore, this.muscleInvolvement);
}

class ExternalWorkoutCnsMapper {
  /// Default muscle groups impacted by various health activities.
  static final Map<HealthWorkoutActivityType, CnsImpact> _impactMap = {
    HealthWorkoutActivityType.RUNNING: const CnsImpact(0.5, {
      'Quads': 0.6,
      'Hamstrings': 0.5,
      'Calves': 0.7,
      'Glutes': 0.4,
    }),
    HealthWorkoutActivityType.CLIMBING: const CnsImpact(0.6, {
      'Lats': 0.8,
      'Back': 0.8,
      'Forearms': 0.9,
      'Biceps': 0.6,
      'Core': 0.4,
      'Quads': 0.3,
    }),
    HealthWorkoutActivityType.BIKING: const CnsImpact(0.4, {
      'Quads': 0.6,
      'Hamstrings': 0.3,
      'Calves': 0.4,
      'Glutes': 0.4,
    }),
    HealthWorkoutActivityType.SWIMMING: const CnsImpact(0.5, {
      'Lats': 0.8,
      'Back': 0.6,
      'Side Delts': 0.6,
      'Core': 0.4,
    }),
    HealthWorkoutActivityType.ROWING: const CnsImpact(0.6, {
      'Back': 0.8,
      'Lats': 0.6,
      'Quads': 0.5,
      'Biceps': 0.4,
      'Core': 0.4,
    }),
    HealthWorkoutActivityType.HIKING: const CnsImpact(0.5, {
      'Quads': 0.6,
      'Hamstrings': 0.5,
      'Calves': 0.7,
      'Glutes': 0.5,
    }),
    // Lower systemic cost than RUNNING's 0.5 — calibrated walking load
    HealthWorkoutActivityType.WALKING: const CnsImpact(0.2, {
      'Quads': 0.25,
      'Hamstrings': 0.2,
      'Calves': 0.3,
      'Glutes': 0.2,
    }),
    HealthWorkoutActivityType.YOGA: const CnsImpact(0.2, {
      'Core': 0.5,
      'Shoulders': 0.3, // Map to Side Delts
    }),
    HealthWorkoutActivityType.STRENGTH_TRAINING: const CnsImpact(0.6, {
      'Chest': 0.4,
      'Back': 0.4,
      'Quads': 0.4,
      'Hamstrings': 0.4,
      'Core': 0.4,
    }),
    // Fallback for high intensity sports
    HealthWorkoutActivityType.BASKETBALL: const CnsImpact(0.6, {
      'Quads': 0.6,
      'Calves': 0.7,
      'Hamstrings': 0.4,
      'Glutes': 0.4,
    }),
    HealthWorkoutActivityType.SOCCER: const CnsImpact(0.7, {
      'Quads': 0.7,
      'Hamstrings': 0.5,
      'Calves': 0.7,
      'Core': 0.4,
    }),
    HealthWorkoutActivityType.TENNIS: const CnsImpact(0.5, {
      'Quads': 0.5,
      'Calves': 0.6,
      'Side Delts': 0.5,
      'Forearms': 0.4,
    }),
    HealthWorkoutActivityType.CROSS_COUNTRY_SKIING: const CnsImpact(0.7, {
      'Quads': 0.7,
      'Glutes': 0.6,
      'Lats': 0.6,
      'Triceps': 0.5,
      'Core': 0.5,
    }),
    HealthWorkoutActivityType.DOWNHILL_SKIING: const CnsImpact(0.5, {
      'Quads': 0.7,
      'Glutes': 0.6,
      'Core': 0.5,
      'Calves': 0.4,
    }),
  };

  static const _defaultImpact = CnsImpact(0.5, {});

  static CnsImpact getImpactFor(HealthWorkoutActivityType type) {
    return _impactMap[type] ?? _defaultImpact;
  }
}
