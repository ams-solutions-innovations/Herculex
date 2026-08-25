import 'package:health/health.dart';

/// Joints the Recovery page lets a user flag, and which of the 19
/// [MuscleRecoveryV3] groups mechanically load each one (0–1 relevance
/// weight) — e.g. heavy triceps/chest pressing loads the elbow via the
/// extensor tendons even though "Elbow" isn't itself a trained muscle group.
/// Coarse and literature-informed, same spirit as
/// `MuscleRecoveryV3.defaultWeeklyMrv`.
abstract final class JointModel {
  static const joints = [
    'Elbow',
    'Shoulder',
    'Wrist',
    'Knee',
    'Hip',
    'Lower Back',
  ];

  static const influencingMuscles = <String, Map<String, double>>{
    'Elbow': {'Triceps': 1.0, 'Biceps': 1.0, 'Forearms': 0.6, 'Chest': 0.3},
    'Shoulder': {
      'Front Delts': 1.0,
      'Side Delts': 0.8,
      'Rear Delts': 0.6,
      'Chest': 0.6,
      'Lats': 0.4,
      'Triceps': 0.3,
    },
    'Wrist': {'Forearms': 1.0, 'Biceps': 0.3, 'Chest': 0.2},
    'Knee': {
      'Quads': 1.0,
      'Hamstrings': 0.6,
      'Calves': 0.4,
      'Adductors': 0.3,
      'Glutes': 0.3,
    },
    'Hip': {
      'Glutes': 1.0,
      'Hamstrings': 0.7,
      'Adductors': 0.7,
      'Abductors': 0.6,
      'Quads': 0.4,
    },
    'Lower Back': {
      'Back': 1.0,
      'Hamstrings': 0.6,
      'Glutes': 0.5,
      'Abs': 0.3,
      'Obliques': 0.3,
    },
  };

  /// Cardio activities whose HealthKit/Health Connect volume folds into a
  /// joint's stress independent of the gym log. Knee-only today (running,
  /// walking and hiking all load it directly); extensible to other joints
  /// later without touching call sites.
  static const cardioActivitiesByJoint = <String, List<HealthWorkoutActivityType>>{
    'Knee': [
      HealthWorkoutActivityType.RUNNING,
      HealthWorkoutActivityType.RUNNING_TREADMILL,
      HealthWorkoutActivityType.WALKING,
      HealthWorkoutActivityType.WALKING_TREADMILL,
      HealthWorkoutActivityType.HIKING,
    ],
  };
}
