import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/features/analytics/presentation/analytics_providers.dart';
import 'package:herculex/features/gamification/domain/achievement_evaluator.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

final achievementEvaluatorProvider = Provider<AchievementEvaluator>((ref) {
  return const AchievementEvaluator();
});

/// Service / helper that connects database snapshot, evaluator, and in-app
/// notification controller together.
class GamificationService {
  final Ref _ref;

  GamificationService(this._ref);

  /// Check a completed set and dispatch any earned in-app achievement notifications.
  Future<void> onSetCompleted({
    required int sessionId,
    required int exerciseId,
    required String exerciseName,
    required String primaryMuscle,
    required double effectiveKg,
    required double weightKg,
    required int reps,
    required List<String> accessoryNames,
    required String equipmentVariant,
    required SetType setType,
  }) async {
    try {
      final snapshot = await _ref.read(trainingSnapshotProvider.future);
      final weightFormat = _ref.read(weightFormatProvider);
      final evaluator = _ref.read(achievementEvaluatorProvider);

      final items = evaluator.evaluateCompletedSet(
        snapshot: snapshot,
        currentSessionId: sessionId,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        primaryMuscle: primaryMuscle,
        effectiveKg: effectiveKg,
        weightKg: weightKg,
        reps: reps,
        accessoryNames: accessoryNames,
        equipmentVariant: equipmentVariant,
        setType: setType,
        weightFormat: weightFormat,
      );

      final notifier = _ref.read(inAppNotificationControllerProvider.notifier);
      final wearSync = _ref.read(wearSyncServiceProvider);
      for (final item in items) {
        notifier.show(item);
        wearSync.sendAchievementNotification(item);
      }
    } catch (_) {
      // Non-critical background gamification evaluation — silently ignore errors.
    }
  }

  /// Check a finished workout session and return unlocked achievements (for share card / summary).
  Future<List<InAppNotificationItem>> onWorkoutFinished({
    required int sessionId,
    required String workoutName,
    required DateTime startedAt,
    required DateTime endedAt,
    required int totalCompletedWorkouts,
  }) async {
    try {
      final snapshot = await _ref.read(trainingSnapshotProvider.future);
      final weightFormat = _ref.read(weightFormatProvider);
      final evaluator = _ref.read(achievementEvaluatorProvider);

      return evaluator.evaluateSessionSummaryAchievements(
        snapshot: snapshot,
        currentSessionId: sessionId,
        workoutName: workoutName,
        startedAt: startedAt,
        endedAt: endedAt,
        weightFormat: weightFormat,
        totalCompletedWorkouts: totalCompletedWorkouts,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Post a test notification for developer / UI preview.
  void triggerDemoNotification(AchievementType type) {
    final notifier = _ref.read(inAppNotificationControllerProvider.notifier);
    switch (type) {
      case AchievementType.weightPr:
        notifier.show(
          InAppNotificationItem.weightPr(
            exerciseName: 'Bench Press',
            weightFormatted: '140 kg',
            diffFormatted: '5 kg',
          ),
        );
        break;
      case AchievementType.repPr:
        notifier.show(
          InAppNotificationItem.repPr(
            exerciseName: 'Incline Dumbbell Press',
            reps: 12,
            weightFormatted: '42 kg',
            previousReps: 10,
          ),
        );
        break;
      case AchievementType.exerciseTonnagePr:
        notifier.show(
          InAppNotificationItem.exerciseTonnagePr(
            exerciseName: 'Barbell Squat',
            volumeFormatted: '5,200 kg',
            diffFormatted: '450 kg',
          ),
        );
        break;
      case AchievementType.muscleGroupVolumePr:
        notifier.show(
          InAppNotificationItem.muscleGroupVolumePr(
            muscleGroup: 'Chest',
            volumeFormatted: '6,400 kg',
            diffFormatted: '800 kg',
          ),
        );
        break;
      case AchievementType.accessoryPr:
        notifier.show(
          InAppNotificationItem.accessoryPr(
            exerciseName: 'Deadlift',
            accessoryLabel: 'Raw (No Belt)',
            weightFormatted: '210 kg',
          ),
        );
        break;
      case AchievementType.workoutTonnagePr:
        notifier.show(
          InAppNotificationItem.workoutTonnagePr(
            workoutName: 'Push Day Hypertrophy',
            tonnageFormatted: '18.4 t',
            diffFormatted: '1.2 t',
          ),
        );
        break;
      case AchievementType.longestWorkout:
        notifier.show(
          InAppNotificationItem.longestWorkout(
            workoutName: 'Full Body Endurance',
            durationFormatted: '1h 45m',
          ),
        );
        break;
      case AchievementType.longestFast:
        notifier.show(
          InAppNotificationItem.longestFast(
            durationFormatted: '24h 30m',
            previousBestFormatted: '18h 00m',
          ),
        );
        break;
      case AchievementType.fastingTarget:
        notifier.show(
          InAppNotificationItem.fastingTarget(
            planName: '16:8 Intermittent Fast',
            durationFormatted: '16h 05m',
          ),
        );
        break;
      case AchievementType.workoutMilestone:
        notifier.show(InAppNotificationItem.workoutMilestone(count: 50));
        break;
      case AchievementType.proteinGoal:
        notifier.show(
          InAppNotificationItem.proteinGoal(
            currentGrams: 185,
            targetGrams: 180,
          ),
        );
        break;
      default:
        notifier.show(
          InAppNotificationItem.weightPr(
            exerciseName: 'Overhead Press',
            weightFormatted: '85 kg',
            diffFormatted: '2.5 kg',
          ),
        );
    }
  }
}

final gamificationServiceProvider = Provider<GamificationService>((ref) {
  return GamificationService(ref);
});
