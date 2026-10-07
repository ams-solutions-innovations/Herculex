import 'package:flutter/material.dart';

/// Categories of achievements and records that can trigger an in-app celebration.
enum AchievementType {
  /// New 1RM or all-time heaviest weight for an exercise.
  weightPr,

  /// Most reps ever achieved at a specific weight.
  repPr,

  /// All-time highest single-session tonnage/volume for an exercise.
  exerciseTonnagePr,

  /// All-time highest volume for a muscle group (e.g. Chest) in a single workout.
  muscleGroupVolumePr,

  /// All-time record for a specific accessory combo (e.g. Raw / No Belt).
  accessoryPr,

  /// All-time highest total session volume/tonnage for a full workout.
  workoutTonnagePr,

  /// All-time longest workout session completed.
  longestWorkout,

  /// All-time longest completed fast.
  longestFast,

  /// Target fasting duration unlocked (e.g. 16:8 goal reached).
  fastingTarget,

  /// Streak milestone for workouts or fasting.
  streakMilestone,

  /// Total workout count milestone (e.g. 10th, 50th, 100th workout).
  workoutMilestone,

  /// Daily protein or macro target reached.
  proteinGoal,

  /// Minimum calories or protein floor reached for the day.
  minimumReached,

  /// Exercise substitution or replacement in a workout.
  exerciseSubstitution,

  /// General workout action notification (e.g. set deleted, target applied).
  workoutAction,

  /// Extensible custom celebration.
  custom,
}

/// Entrance-animation total (drop + settle/expand + content reveal) for the
/// circle->pill notification widget. Kept in sync with
/// [in_app_notification_overlay.dart]'s `_enterCtrl` duration.
const kAchievementEnterDuration = Duration(milliseconds: 1160);

/// Default time the fully-expanded pill stays visible before collapsing.
/// Tunable per the design handoff rather than hardcoded per notification.
const kAchievementDefaultHold = Duration(milliseconds: 1800);

/// Represents a single in-app notification payload to display in the dropping pill HUD.
class InAppNotificationItem {
  final String id;
  final AchievementType type;
  final String badgeText;
  final String title;
  final String valueText;
  final String? subtitle;

  /// Label line shown above the value row, e.g. "Bench Press · new weight PR".
  final String label;

  /// The headline PR value, e.g. "105 kg" or "8 reps".
  final String value;

  /// The delta from the previous record, e.g. "+5 kg". Null if there's no
  /// meaningful previous value to diff against.
  final String? delta;

  final IconData icon;
  final Color primaryColor;
  final Color? secondaryColor;
  final VoidCallback? onTap;
  final Duration duration;

  /// Optional action button label (e.g. "Undo").
  final String? actionLabel;

  /// Optional callback invoked when the user taps the action button.
  final VoidCallback? onAction;

  const InAppNotificationItem({
    required this.id,
    required this.type,
    required this.badgeText,
    required this.title,
    required this.valueText,
    this.subtitle,
    required this.label,
    required this.value,
    this.delta,
    required this.icon,
    this.primaryColor = const Color(0xFFFFD700), // Gold default
    this.secondaryColor,
    this.onTap,
    this.actionLabel,
    this.onAction,
    // kAchievementEnterDuration (1160ms) + kAchievementDefaultHold (1800ms):
    // the notifier's auto-dismiss Timer should fire exactly when the hold ends.
    this.duration = const Duration(milliseconds: 2960),
  });

  /// Factory helper for Weight / 1RM PR.
  factory InAppNotificationItem.weightPr({
    required String exerciseName,
    required String weightFormatted,
    String? diffFormatted,
    String? accessoryTag,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'weight_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.weightPr,
      badgeText: accessoryTag != null && accessoryTag.isNotEmpty
          ? '🏆 NEW PR • ${accessoryTag.toUpperCase()}'
          : '🏆 NEW 1RM PR',
      title: exerciseName,
      valueText: diffFormatted != null && diffFormatted.isNotEmpty
          ? '$weightFormatted (+$diffFormatted)'
          : weightFormatted,
      subtitle: 'All-time estimated 1RM record crushed!',
      label: accessoryTag != null && accessoryTag.isNotEmpty
          ? '$exerciseName · new $accessoryTag PR'
          : '$exerciseName · new weight PR',
      value: weightFormatted,
      delta: diffFormatted != null && diffFormatted.isNotEmpty
          ? '+$diffFormatted'
          : null,
      icon: Icons.emoji_events_rounded,
      primaryColor: const Color(0xFFFFD60A), // Weight PR yellow
      secondaryColor: const Color(0xFFFFA000),
      onTap: onTap,
    );
  }

  /// Factory helper for Rep PR at a weight.
  factory InAppNotificationItem.repPr({
    required String exerciseName,
    required int reps,
    required String weightFormatted,
    int? previousReps,
    VoidCallback? onTap,
  }) {
    final diff = previousReps != null ? ' (+${reps - previousReps} reps)' : '';
    return InAppNotificationItem(
      id: 'rep_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.repPr,
      badgeText: '⚡ REP RECORD',
      title: exerciseName,
      valueText: '$weightFormatted × $reps reps$diff',
      subtitle: 'Most reps ever logged at this weight!',
      label: '$exerciseName · new rep PR',
      value: '$reps reps',
      delta: previousReps != null ? '+${reps - previousReps}' : null,
      icon: Icons.bolt_rounded,
      primaryColor: const Color(0xFFFF453A), // Rep PR red
      secondaryColor: const Color(0xFFFF3D00),
      onTap: onTap,
    );
  }

  /// Factory helper for Exercise Volume / Tonnage PR.
  factory InAppNotificationItem.exerciseTonnagePr({
    required String exerciseName,
    required String volumeFormatted,
    String? diffFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'ex_volume_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.exerciseTonnagePr,
      badgeText: '🔥 EXERCISE VOLUME PR',
      title: exerciseName,
      valueText: diffFormatted != null && diffFormatted.isNotEmpty
          ? '$volumeFormatted (+$diffFormatted)'
          : volumeFormatted,
      subtitle: 'Highest single-session volume for this exercise!',
      label: '$exerciseName · new volume PR',
      value: volumeFormatted,
      delta: diffFormatted != null && diffFormatted.isNotEmpty
          ? '+$diffFormatted'
          : null,
      icon: Icons.local_fire_department_rounded,
      primaryColor: const Color(0xFF0A84FF), // Volume PR blue
      secondaryColor: const Color(0xFFFF1744),
      onTap: onTap,
    );
  }

  /// Factory helper for Muscle Group Volume PR per workout (e.g. Chest).
  factory InAppNotificationItem.muscleGroupVolumePr({
    required String muscleGroup,
    required String volumeFormatted,
    String? diffFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'muscle_volume_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.muscleGroupVolumePr,
      badgeText: '👑 ${muscleGroup.toUpperCase()} VOLUME PR',
      title: '$muscleGroup Session Record',
      valueText: diffFormatted != null && diffFormatted.isNotEmpty
          ? '$volumeFormatted (+$diffFormatted)'
          : volumeFormatted,
      subtitle: 'Most volume ever moved for $muscleGroup in one workout!',
      label: '$muscleGroup · new volume PR',
      value: volumeFormatted,
      delta: diffFormatted != null && diffFormatted.isNotEmpty
          ? '+$diffFormatted'
          : null,
      icon: Icons.fitness_center_rounded,
      primaryColor: const Color(0xFF0A84FF), // Volume PR blue
      secondaryColor: const Color(0xFF00B0FF),
      onTap: onTap,
    );
  }

  /// Factory helper for Accessory / Variant PR (e.g. Best Weight Without Belt).
  factory InAppNotificationItem.accessoryPr({
    required String exerciseName,
    required String accessoryLabel,
    required String weightFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'accessory_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.accessoryPr,
      badgeText: '🛡️ ${accessoryLabel.toUpperCase()} RECORD',
      title: exerciseName,
      valueText: weightFormatted,
      subtitle: 'Personal best for $accessoryLabel performance!',
      label: '$exerciseName · new $accessoryLabel PR',
      value: weightFormatted,
      icon: Icons.shield_rounded,
      primaryColor: const Color(0xFFFFD60A), // Weight-family PR yellow
      secondaryColor: const Color(0xFF7C4DFF),
      onTap: onTap,
    );
  }

  /// Factory helper for Total Workout Tonnage PR.
  factory InAppNotificationItem.workoutTonnagePr({
    required String workoutName,
    required String tonnageFormatted,
    String? diffFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'workout_tonnage_pr_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutTonnagePr,
      badgeText: '💎 WORKOUT TONNAGE RECORD',
      title: workoutName.isNotEmpty ? workoutName : 'Workout Session',
      valueText: diffFormatted != null && diffFormatted.isNotEmpty
          ? '$tonnageFormatted (+$diffFormatted)'
          : tonnageFormatted,
      subtitle: 'All-time heaviest workout session in history!',
      label:
          '${workoutName.isNotEmpty ? workoutName : 'Workout'} · new volume PR',
      value: tonnageFormatted,
      delta: diffFormatted != null && diffFormatted.isNotEmpty
          ? '+$diffFormatted'
          : null,
      icon: Icons.diamond_rounded,
      primaryColor: const Color(0xFF0A84FF), // Volume PR blue
      secondaryColor: const Color(0xFF7C4DFF),
      onTap: onTap,
    );
  }

  /// Factory helper for Longest Workout session.
  factory InAppNotificationItem.longestWorkout({
    required String workoutName,
    required String durationFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'longest_workout_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.longestWorkout,
      badgeText: '⏱️ LONGEST WORKOUT RECORD',
      title: workoutName.isNotEmpty ? workoutName : 'Workout Session',
      valueText: durationFormatted,
      subtitle: 'New personal best for workout duration & stamina!',
      label:
          '${workoutName.isNotEmpty ? workoutName : 'Workout'} · new duration PR',
      value: durationFormatted,
      icon: Icons.timer_rounded,
      primaryColor: const Color(0xFFFF6D00), // Amber flame
      secondaryColor: const Color(0xFFFFD600),
      onTap: onTap,
    );
  }

  /// Factory helper for Longest Fast completed.
  factory InAppNotificationItem.longestFast({
    required String durationFormatted,
    String? previousBestFormatted,
    VoidCallback? onTap,
  }) {
    final diff = previousBestFormatted != null
        ? ' (beat $previousBestFormatted)'
        : '';
    return InAppNotificationItem(
      id: 'longest_fast_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.longestFast,
      badgeText: '🔥 LONGEST FAST COMPLETED',
      title: 'Fasting Milestone',
      valueText: '$durationFormatted$diff',
      subtitle: 'All-time longest continuous fast in history!',
      label: 'Fasting · new longest fast',
      value: durationFormatted,
      delta: previousBestFormatted != null
          ? 'prev $previousBestFormatted'
          : null,
      icon: Icons.whatshot_rounded,
      primaryColor: const Color(0xFFFF9100), // Orange / Flame
      secondaryColor: const Color(0xFFFF5252),
      onTap: onTap,
    );
  }

  /// Factory helper for Fasting Target reached.
  factory InAppNotificationItem.fastingTarget({
    required String planName,
    required String durationFormatted,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'fasting_target_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.fastingTarget,
      badgeText: '🎯 FASTING GOAL REACHED',
      title: planName,
      valueText: durationFormatted,
      subtitle: 'Target fasting protocol successfully completed!',
      label: '$planName · goal reached',
      value: durationFormatted,
      icon: Icons.task_alt_rounded,
      primaryColor: const Color(0xFF00E676), // Vibrant Emerald
      secondaryColor: const Color(0xFF1DE9B6),
      onTap: onTap,
    );
  }

  /// Factory helper for Workout Milestone (10th, 50th, 100th).
  factory InAppNotificationItem.workoutMilestone({
    required int count,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'workout_milestone_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutMilestone,
      badgeText: '🌟 MILESTONE UNLOCKED',
      title: 'Workout Consistency',
      valueText: '$count Workouts Completed!',
      subtitle: 'Incredible dedication and discipline!',
      label: 'Workout milestone',
      value: '$count workouts',
      icon: Icons.military_tech_rounded,
      primaryColor: const Color(0xFFFFD700), // Gold
      secondaryColor: const Color(0xFFFF6D00),
      onTap: onTap,
    );
  }

  /// Factory helper for Protein Goal hit.
  factory InAppNotificationItem.proteinGoal({
    required double currentGrams,
    required double targetGrams,
    VoidCallback? onTap,
  }) {
    return InAppNotificationItem(
      id: 'protein_goal_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.proteinGoal,
      badgeText: '💪 PROTEIN GOAL HIT',
      title: 'Daily Nutrition Target',
      valueText: '${currentGrams.round()}g / ${targetGrams.round()}g',
      subtitle: 'Daily anabolic target achieved!',
      label: 'Daily protein goal',
      value: '${currentGrams.round()}g',
      delta: '/${targetGrams.round()}g',
      icon: Icons.egg_alt_rounded,
      primaryColor: const Color(0xFF00E5FF), // Cyan
      secondaryColor: const Color(0xFF00B0FF),
      onTap: onTap,
    );
  }

  /// Factory helper for the daily minimum calories / protein floor being met.
  factory InAppNotificationItem.minimumReached({
    required bool isProtein,
    required double current,
    required int minimum,
    VoidCallback? onTap,
  }) {
    final unit = isProtein ? 'g' : ' kcal';
    return InAppNotificationItem(
      id:
          'min_reached_${isProtein ? 'protein' : 'kcal'}_'
          '${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.minimumReached,
      badgeText: isProtein ? 'MIN PROTEIN REACHED' : 'MIN CALORIES REACHED',
      title: 'Daily Minimum',
      valueText: '${current.round()}$unit / $minimum$unit',
      subtitle: isProtein
          ? 'You hit your minimum protein for today!'
          : 'You hit your minimum calories for today!',
      label: isProtein ? 'Minimum protein' : 'Minimum calories',
      value: '${current.round()}$unit',
      delta: '/$minimum$unit',
      icon: isProtein
          ? Icons.egg_alt_rounded
          : Icons.local_fire_department_rounded,
      primaryColor: isProtein
          ? const Color(0xFF00E5FF)
          : const Color(0xFFFF9F0A),
      secondaryColor: isProtein
          ? const Color(0xFF00B0FF)
          : const Color(0xFFFF6D00),
      onTap: onTap,
    );
  }

  /// Factory helper for Exercise Replacement / Substitution in a workout.
  factory InAppNotificationItem.exerciseReplaced({
    required String exerciseName,
    bool permanently = false,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return InAppNotificationItem(
      id: 'ex_replace_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.exerciseSubstitution,
      badgeText: permanently ? '🔄 PERMANENT REPLACEMENT' : '🔄 SUBSTITUTION',
      title: exerciseName,
      valueText: permanently
          ? 'Permanently replaced with $exerciseName'
          : 'Substituted to $exerciseName',
      subtitle: permanently
          ? 'Workout routine template updated'
          : 'Session exercise substituted',
      label: permanently ? 'Permanent replacement' : 'Exercise substituted',
      value: exerciseName,
      icon: Icons.swap_horiz_rounded,
      primaryColor: const Color(0xFF00E676), // Vibrant emerald
      secondaryColor: const Color(0xFF1DE9B6),
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: const Duration(milliseconds: 3200),
    );
  }

  /// Factory helper for workout actions (e.g. set deleted, target applied).
  factory InAppNotificationItem.workoutAction({
    required String label,
    required String value,
    String? delta,
    IconData icon = Icons.check_circle_rounded,
    Color primaryColor = const Color(0xFF00E676),
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    return InAppNotificationItem(
      id: 'workout_act_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutAction,
      badgeText: 'WORKOUT ACTION',
      title: value,
      valueText: value,
      label: label,
      value: value,
      delta: delta,
      icon: icon,
      primaryColor: primaryColor,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Factory helper for general in-app success messages.
  factory InAppNotificationItem.success({
    required String label,
    required String value,
    IconData icon = Icons.check_circle_rounded,
    Color primaryColor = const Color(0xFF00E676),
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    return InAppNotificationItem(
      id: 'success_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutAction,
      badgeText: 'SUCCESS',
      title: value,
      valueText: value,
      label: label,
      value: value,
      icon: icon,
      primaryColor: primaryColor,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Factory helper for neutral information (a sync finished, a setting took
  /// effect) — same pill as a PR, in a calm blue.
  factory InAppNotificationItem.info({
    required String label,
    required String value,
    IconData icon = Icons.info_rounded,
    Color primaryColor = const Color(0xFF64B5F6),
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    return InAppNotificationItem(
      id: 'info_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutAction,
      badgeText: 'INFO',
      title: value,
      valueText: value,
      label: label,
      value: value,
      icon: icon,
      primaryColor: primaryColor,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Factory helper for failures the user should notice — red pill, held a
  /// little longer than a confirmation.
  factory InAppNotificationItem.error({
    required String label,
    required String value,
    IconData icon = Icons.error_rounded,
    Color primaryColor = const Color(0xFFFF453A),
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    return InAppNotificationItem(
      id: 'error_${DateTime.now().microsecondsSinceEpoch}',
      type: AchievementType.workoutAction,
      badgeText: 'ERROR',
      title: value,
      valueText: value,
      label: label,
      value: value,
      icon: icon,
      primaryColor: primaryColor,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }
}
