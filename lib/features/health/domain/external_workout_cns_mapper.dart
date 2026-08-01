import 'package:health/health.dart';

class CnsImpact {
  final double baseCnsScore; // 0.1 to 1.0
  final Map<String, double> muscleInvolvement; // Role weight per muscle (0.0 to 1.0)

  const CnsImpact(this.baseCnsScore, this.muscleInvolvement);
}

class ExternalWorkoutCnsMapper {
  /// Default muscle groups impacted by various health activities.
  static final Map<HealthWorkoutActivityType, CnsImpact> _impactMap = {
    HealthWorkoutActivityType.RUNNING: const CnsImpact(0.8, {
      'Quads': 1.0,
      'Hamstrings': 0.8,
      'Calves': 1.0,
      'Glutes': 0.5,
    }),
    HealthWorkoutActivityType.CLIMBING: const CnsImpact(0.9, {
      'Lats': 1.0,
      'Back': 1.0,
      'Forearms': 1.0,
      'Biceps': 0.8,
      'Core': 0.5,
      'Quads': 0.6,
    }),
    HealthWorkoutActivityType.BIKING: const CnsImpact(0.6, {
      'Quads': 1.0,
      'Hamstrings': 0.5,
      'Calves': 0.6,
      'Glutes': 0.6,
    }),
    HealthWorkoutActivityType.SWIMMING: const CnsImpact(0.7, {
      'Lats': 1.0,
      'Back': 0.8,
      'Side Delts': 0.8,
      'Core': 0.6,
    }),
    HealthWorkoutActivityType.ROWING: const CnsImpact(0.8, {
      'Back': 1.0,
      'Lats': 0.8,
      'Quads': 0.8,
      'Biceps': 0.5,
      'Core': 0.5,
    }),
    HealthWorkoutActivityType.HIKING: const CnsImpact(0.7, {
      'Quads': 1.0,
      'Hamstrings': 0.8,
      'Calves': 1.0,
      'Glutes': 0.8,
    }),
    HealthWorkoutActivityType.YOGA: const CnsImpact(0.2, {
      'Core': 0.6,
      'Shoulders': 0.4, // Map to Side Delts
    }),
    HealthWorkoutActivityType.STRENGTH_TRAINING: const CnsImpact(0.8, {
      'Chest': 0.5,
      'Back': 0.5,
      'Quads': 0.5,
      'Hamstrings': 0.5,
      'Core': 0.5,
    }),
    // Fallback for high intensity sports
    HealthWorkoutActivityType.BASKETBALL: const CnsImpact(0.8, {
      'Quads': 0.8,
      'Calves': 1.0,
      'Hamstrings': 0.6,
      'Glutes': 0.5,
    }),
    HealthWorkoutActivityType.SOCCER: const CnsImpact(0.9, {
      'Quads': 1.0,
      'Hamstrings': 0.8,
      'Calves': 1.0,
      'Core': 0.5,
    }),
    HealthWorkoutActivityType.TENNIS: const CnsImpact(0.7, {
      'Quads': 0.8,
      'Calves': 0.8,
      'Side Delts': 0.6,
      'Forearms': 0.5,
    }),
    HealthWorkoutActivityType.CROSS_COUNTRY_SKIING: const CnsImpact(0.9, {
      'Quads': 1.0,
      'Glutes': 0.8,
      'Lats': 0.8,
      'Triceps': 0.6,
      'Core': 0.6,
    }),
    HealthWorkoutActivityType.DOWNHILL_SKIING: const CnsImpact(0.7, {
      'Quads': 1.0,
      'Glutes': 0.8,
      'Core': 0.7,
      'Calves': 0.5,
    }),
  };

  static const _defaultImpact = CnsImpact(0.5, {});

  static CnsImpact getImpactFor(HealthWorkoutActivityType type) {
    return _impactMap[type] ?? _defaultImpact;
  }
}
