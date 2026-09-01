import 'dart:math' as math;

import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// Evaluates workouts, completed sets, and fasts for new personal records
/// and milestones to trigger in-app gamification notifications.
class AchievementEvaluator {
  const AchievementEvaluator();

  /// Evaluates a completed set against historical training data and returns
  /// any unlocked achievement notifications (ordered by prestige).
  List<InAppNotificationItem> evaluateCompletedSet({
    required TrainingSnapshot snapshot,
    required int currentSessionId,
    required int exerciseId,
    required String exerciseName,
    required String primaryMuscle,
    required double effectiveKg,
    required double weightKg,
    required int reps,
    required List<String> accessoryNames,
    required String equipmentVariant,
    required SetType setType,
    required WeightFormat weightFormat,
  }) {
    if (reps <= 0 || effectiveKg <= 0) return const [];

    final notifications = <InAppNotificationItem>[];

    // Filter past completed sets for this exercise from previous workouts
    final pastSets = snapshot.sets
        .where(
          (rs) =>
              rs.exercise.id == exerciseId &&
              rs.session.id != currentSessionId &&
              rs.set.isCompleted &&
              !rs.set.isWarmup &&
              rs.set.reps > 0 &&
              rs.effectiveKg > 0,
        )
        .toList();

    // 1. Estimated 1RM & Weight PR
    final currentE1Rm = OneRepMax.estimate(weightKg: effectiveKg, reps: reps);
    if (currentE1Rm != null) {
      double? pastBestE1Rm;
      double? pastBestWeight;

      for (final rs in pastSets) {
        final est = OneRepMax.estimate(
          weightKg: rs.effectiveKg,
          reps: rs.set.reps,
        );
        if (est != null && (pastBestE1Rm == null || est > pastBestE1Rm)) {
          pastBestE1Rm = est;
        }
        if (pastBestWeight == null || rs.effectiveKg > pastBestWeight) {
          pastBestWeight = rs.effectiveKg;
        }
      }

      if (pastBestE1Rm != null && currentE1Rm > pastBestE1Rm + 0.4) {
        final diffKg = currentE1Rm - pastBestE1Rm;
        final diffStr = weightFormat.format(diffKg, decimals: 1);
        final currentStr = weightFormat.format(currentE1Rm, decimals: 0);

        notifications.add(
          InAppNotificationItem.weightPr(
            exerciseName: exerciseName,
            weightFormatted: currentStr,
            diffFormatted: diffStr,
          ),
        );
      }
    }

    // 2. Rep PR at this specific weight (within 0.5kg margin)
    final sameWeightPastSets = pastSets
        .where((rs) => (rs.effectiveKg - effectiveKg).abs() < 0.6)
        .toList();

    if (sameWeightPastSets.isNotEmpty) {
      final maxPastRepsAtWeight = sameWeightPastSets
          .map((rs) => rs.set.reps)
          .reduce(math.max);
      if (reps > maxPastRepsAtWeight) {
        notifications.add(
          InAppNotificationItem.repPr(
            exerciseName: exerciseName,
            reps: reps,
            weightFormatted: weightFormat.format(effectiveKg, decimals: 0),
            previousReps: maxPastRepsAtWeight,
          ),
        );
      }
    }

    // 3. Accessory PR: Raw / No-Belt Record or specific accessory combo
    final isRawNoBelt = !accessoryNames.any(
      (a) => a.toLowerCase().contains('belt'),
    );

    if (isRawNoBelt && pastSets.isNotEmpty) {
      final pastRawSets = pastSets.where(
        (rs) => !rs.accessoryNames.any((a) => a.toLowerCase().contains('belt')),
      );

      if (pastRawSets.isNotEmpty) {
        final pastBestRawKg = pastRawSets
            .map((rs) => rs.effectiveKg)
            .reduce(math.max);
        if (effectiveKg > pastBestRawKg + 0.4) {
          notifications.add(
            InAppNotificationItem.accessoryPr(
              exerciseName: exerciseName,
              accessoryLabel: 'Raw (No Belt)',
              weightFormatted: weightFormat.format(effectiveKg, decimals: 0),
            ),
          );
        }
      }
    }

    // 4. Single-Exercise Session Tonnage/Volume PR
    if (pastSets.isNotEmpty) {
      final pastSetsBySession = <int, double>{};
      for (final rs in pastSets) {
        pastSetsBySession[rs.session.id] =
            (pastSetsBySession[rs.session.id] ?? 0.0) + rs.tonnageKg;
      }
      final pastBestExTonnage = pastSetsBySession.values.isEmpty
          ? 0.0
          : pastSetsBySession.values.reduce(math.max);

      if (pastBestExTonnage > 0) {
        final currentExSets = snapshot.sets
            .where(
              (rs) =>
                  rs.exercise.id == exerciseId &&
                  rs.session.id == currentSessionId &&
                  rs.set.isCompleted &&
                  !rs.set.isWarmup,
            )
            .toList();

        final currentPriorVol = currentExSets.fold<double>(
          0.0,
          (sum, rs) => sum + rs.tonnageKg,
        );
        final currentTotalVol = currentPriorVol + (effectiveKg * reps);

        if (currentTotalVol > pastBestExTonnage + 20.0 &&
            currentPriorVol <= pastBestExTonnage) {
          final diff = currentTotalVol - pastBestExTonnage;
          final currentStr = currentTotalVol >= 1000
              ? '${(currentTotalVol / 1000).toStringAsFixed(1)} t'
              : '${currentTotalVol.round()} kg';
          final diffStr = diff >= 1000
              ? '${(diff / 1000).toStringAsFixed(1)} t'
              : '${diff.round()} kg';

          notifications.add(
            InAppNotificationItem.exerciseTonnagePr(
              exerciseName: exerciseName,
              volumeFormatted: currentStr,
              diffFormatted: diffStr,
            ),
          );
        }
      }
    }

    return notifications;
  }

  /// Evaluates a completed workout session for total tonnage, muscle group
  /// volume records (e.g. Chest volume PR), longest workout, and milestones.
  List<InAppNotificationItem> evaluateFinishedWorkout({
    required TrainingSnapshot snapshot,
    required int currentSessionId,
    required String workoutName,
    required DateTime startedAt,
    required DateTime endedAt,
    required WeightFormat weightFormat,
    required int totalCompletedWorkouts,
  }) {
    final notifications = <InAppNotificationItem>[];

    // Current session sets
    final currentSessionSets = [
      for (final rs in snapshot.sets)
        if (rs.session.id == currentSessionId &&
            rs.set.isCompleted &&
            !rs.set.isWarmup)
          rs,
    ];

    // Past session sets grouped by session ID
    final pastSetsBySession = <int, List<ResolvedSet>>{};
    for (final rs in snapshot.sets) {
      if (rs.session.id != currentSessionId &&
          rs.set.isCompleted &&
          !rs.set.isWarmup) {
        pastSetsBySession.putIfAbsent(rs.session.id, () => []).add(rs);
      }
    }

    // 1. Total Workout Session Tonnage PR
    final currentTonnage = currentSessionSets.fold<double>(
      0.0,
      (sum, rs) => sum + rs.tonnageKg,
    );

    if (currentTonnage > 0 && pastSetsBySession.isNotEmpty) {
      var pastBestTonnage = 0.0;
      for (final sessionSets in pastSetsBySession.values) {
        final sessionTonnage = sessionSets.fold<double>(
          0.0,
          (sum, rs) => sum + rs.tonnageKg,
        );
        if (sessionTonnage > pastBestTonnage) {
          pastBestTonnage = sessionTonnage;
        }
      }

      if (pastBestTonnage > 0 && currentTonnage > pastBestTonnage + 50.0) {
        final diff = currentTonnage - pastBestTonnage;
        final currentStr = currentTonnage >= 1000
            ? '${(currentTonnage / 1000).toStringAsFixed(1)} t'
            : '${currentTonnage.round()} kg';
        final diffStr = diff >= 1000
            ? '${(diff / 1000).toStringAsFixed(1)} t'
            : '${diff.round()} kg';

        notifications.add(
          InAppNotificationItem.workoutTonnagePr(
            workoutName: workoutName,
            tonnageFormatted: currentStr,
            diffFormatted: diffStr,
          ),
        );
      }
    }

    // 2. Muscle Group Volume PR per Workout (e.g. Chest Volume Record)
    final musclesByExercise = <int, List<String>>{};
    for (final m in snapshot.exerciseMuscles) {
      if (m.role != 'primary') continue;
      musclesByExercise
          .putIfAbsent(m.exerciseId, () => [])
          .add(MuscleRecoveryV3.alias[m.muscle] ?? m.muscle);
    }

    // Current session volume per muscle group
    final currentMuscleVolume = <String, double>{};
    for (final rs in currentSessionSets) {
      final muscles =
          musclesByExercise[rs.exercise.id] ??
          [
            MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
                rs.exercise.primaryMuscle,
          ];
      for (final m in muscles) {
        currentMuscleVolume[m] = (currentMuscleVolume[m] ?? 0.0) + rs.tonnageKg;
      }
    }

    // Past maximum volume per muscle group in a single session
    final pastMaxMuscleVolume = <String, double>{};
    for (final sessionSets in pastSetsBySession.values) {
      final sessionMuscleVolume = <String, double>{};
      for (final rs in sessionSets) {
        final muscles =
            musclesByExercise[rs.exercise.id] ??
            [
              MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
                  rs.exercise.primaryMuscle,
            ];
        for (final m in muscles) {
          sessionMuscleVolume[m] =
              (sessionMuscleVolume[m] ?? 0.0) + rs.tonnageKg;
        }
      }
      for (final entry in sessionMuscleVolume.entries) {
        if (entry.value > (pastMaxMuscleVolume[entry.key] ?? 0.0)) {
          pastMaxMuscleVolume[entry.key] = entry.value;
        }
      }
    }

    // Check each trained muscle group for a record
    for (final entry in currentMuscleVolume.entries) {
      final muscle = entry.key;
      final currentVol = entry.value;
      final pastMax = pastMaxMuscleVolume[muscle] ?? 0.0;

      // Only notify if there is a previous history for this muscle and current breaks it by a noticeable margin
      if (pastMax > 0 && currentVol > pastMax + 30.0 && currentVol > 100.0) {
        final diff = currentVol - pastMax;
        final volStr = currentVol >= 1000
            ? '${(currentVol / 1000).toStringAsFixed(1)} t'
            : '${currentVol.round()} kg';
        final diffStr = diff >= 1000
            ? '${(diff / 1000).toStringAsFixed(1)} t'
            : '${diff.round()} kg';

        notifications.add(
          InAppNotificationItem.muscleGroupVolumePr(
            muscleGroup: muscle,
            volumeFormatted: volStr,
            diffFormatted: diffStr,
          ),
        );
      }
    }

    // 3. Longest Workout Duration Record
    final currentDuration = endedAt.difference(startedAt);
    if (currentDuration.inMinutes >= 30 && pastSetsBySession.isNotEmpty) {
      var pastLongestMinutes = 0;
      final pastSessions = snapshot.sets
          .map((s) => s.session)
          .where((s) => s.id != currentSessionId && s.endedAt != null)
          .toSet();

      for (final s in pastSessions) {
        final dur = s.endedAt!.difference(s.startedAt).inMinutes;
        if (dur > pastLongestMinutes) {
          pastLongestMinutes = dur;
        }
      }

      if (pastLongestMinutes > 0 &&
          currentDuration.inMinutes > pastLongestMinutes + 5) {
        final h = currentDuration.inHours;
        final m = currentDuration.inMinutes.remainder(60);
        final durStr = h > 0 ? '${h}h ${m}m' : '${m}m';

        notifications.add(
          InAppNotificationItem.longestWorkout(
            workoutName: workoutName,
            durationFormatted: durStr,
          ),
        );
      }
    }

    // 4. Workout Count Milestones (1st, 10th, 25th, 50th, 100th, 250th, 500th, 1000th)
    const milestoneCounts = {
      1,
      5,
      10,
      25,
      50,
      75,
      100,
      150,
      200,
      250,
      500,
      1000,
    };
    if (milestoneCounts.contains(totalCompletedWorkouts)) {
      notifications.add(
        InAppNotificationItem.workoutMilestone(count: totalCompletedWorkouts),
      );
    }

    return notifications;
  }

  /// Evaluates a completed fast for longest fast record and target completion.
  List<InAppNotificationItem> evaluateFinishedFast({
    required Duration fastDuration,
    required List<FastingSessionData> pastSessions,
    String? planName,
    int? targetSeconds,
  }) {
    final notifications = <InAppNotificationItem>[];

    // Format duration helper
    String formatDuration(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    // 1. Longest Fast Record
    final completedPast = pastSessions
        .where((s) => s.endedAt != null && s.completed)
        .toList();

    if (completedPast.isNotEmpty) {
      Duration pastLongest = Duration.zero;
      for (final s in completedPast) {
        final d = s.endedAt!.difference(s.startedAt);
        if (d > pastLongest) {
          pastLongest = d;
        }
      }

      // Check if current fast exceeds previous longest by at least 10 minutes
      if (pastLongest.inMinutes > 60 &&
          fastDuration > pastLongest + const Duration(minutes: 10)) {
        notifications.add(
          InAppNotificationItem.longestFast(
            durationFormatted: formatDuration(fastDuration),
            previousBestFormatted: formatDuration(pastLongest),
          ),
        );
      }
    }

    // 2. Target Fast Completed
    if (targetSeconds != null && targetSeconds > 0) {
      if (fastDuration.inSeconds >= targetSeconds) {
        notifications.add(
          InAppNotificationItem.fastingTarget(
            planName: planName ?? 'Target Fast',
            durationFormatted: formatDuration(fastDuration),
          ),
        );
      }
    }

    return notifications;
  }

  /// Evaluates all records and achievements achieved during this workout session
  /// (workout tonnage PR, muscle group volume PRs, exercise 1RM PRs, longest workout, milestones).
  List<InAppNotificationItem> evaluateSessionSummaryAchievements({
    required TrainingSnapshot snapshot,
    required int currentSessionId,
    required String workoutName,
    required DateTime startedAt,
    required DateTime endedAt,
    required WeightFormat weightFormat,
    required int totalCompletedWorkouts,
  }) {
    final achievements = <InAppNotificationItem>[];

    // 1. Evaluate workout-level records (tonnage, muscle groups, longest workout, milestone)
    final workoutRecords = evaluateFinishedWorkout(
      snapshot: snapshot,
      currentSessionId: currentSessionId,
      workoutName: workoutName,
      startedAt: startedAt,
      endedAt: endedAt,
      weightFormat: weightFormat,
      totalCompletedWorkouts: totalCompletedWorkouts,
    );
    achievements.addAll(workoutRecords);

    // 2. Evaluate all exercise-level PRs achieved in this workout
    final currentSessionSets = snapshot.sets
        .where(
          (rs) =>
              rs.session.id == currentSessionId &&
              rs.set.isCompleted &&
              !rs.set.isWarmup &&
              rs.set.reps > 0 &&
              rs.effectiveKg > 0,
        )
        .toList();

    final exerciseIds = currentSessionSets.map((rs) => rs.exercise.id).toSet();

    for (final exId in exerciseIds) {
      final sessionExSets = currentSessionSets
          .where((rs) => rs.exercise.id == exId)
          .toList();
      if (sessionExSets.isEmpty) continue;
      final exName = sessionExSets.first.exercise.name;

      final pastExSets = snapshot.sets
          .where(
            (rs) =>
                rs.exercise.id == exId &&
                rs.session.id != currentSessionId &&
                rs.set.isCompleted &&
                !rs.set.isWarmup &&
                rs.set.reps > 0 &&
                rs.effectiveKg > 0,
          )
          .toList();

      if (pastExSets.isEmpty) continue;

      // Check best 1RM in current session vs past best 1RM
      double? currentBestE1Rm;
      for (final rs in sessionExSets) {
        final est = OneRepMax.estimate(
          weightKg: rs.effectiveKg,
          reps: rs.set.reps,
        );
        if (est != null && (currentBestE1Rm == null || est > currentBestE1Rm)) {
          currentBestE1Rm = est;
        }
      }

      double? pastBestE1Rm;
      for (final rs in pastExSets) {
        final est = OneRepMax.estimate(
          weightKg: rs.effectiveKg,
          reps: rs.set.reps,
        );
        if (est != null && (pastBestE1Rm == null || est > pastBestE1Rm)) {
          pastBestE1Rm = est;
        }
      }

      if (currentBestE1Rm != null &&
          pastBestE1Rm != null &&
          currentBestE1Rm > pastBestE1Rm + 0.4) {
        final diffKg = currentBestE1Rm - pastBestE1Rm;
        achievements.add(
          InAppNotificationItem.weightPr(
            exerciseName: exName,
            weightFormatted: weightFormat.format(currentBestE1Rm, decimals: 0),
            diffFormatted: weightFormat.format(diffKg, decimals: 1),
          ),
        );
      }
    }

    return achievements;
  }
}
