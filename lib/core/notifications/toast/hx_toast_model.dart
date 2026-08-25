import 'package:flutter/material.dart';

/// Hold duration before the toast auto-dismisses. Matches the design spec's
/// "auto-dismiss after 1.8 s".
const kHxToastDuration = Duration(milliseconds: 1800);

/// A single centered "squircle" toast payload — the everyday save/sync
/// confirmation and error toast that replaces plain [SnackBar]s app-wide.
///
/// Distinct from `InAppNotificationItem` (the achievement/PR dropping-pill
/// HUD in `in_app_notification_model.dart`): this is for routine
/// confirmations, not celebrations, and the two systems run independently.
class HxToastItem {
  final String id;
  final IconData icon;
  final String title;
  final String message;
  final Color accentColor;
  final VoidCallback? onTap;
  final Duration duration;

  const HxToastItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.message,
    required this.accentColor,
    this.onTap,
    this.duration = kHxToastDuration,
  });

  factory HxToastItem.profileSaved() {
    return HxToastItem(
      id: 'profile_saved_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.fitness_center_rounded,
      title: 'Profile saved',
      message: 'Stats and targets are up to date',
      accentColor: const Color(0xFF30D158),
    );
  }

  factory HxToastItem.saveFailed({String? message}) {
    final trimmed = message?.trim();
    return HxToastItem(
      id: 'save_failed_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.error_rounded,
      title: 'Could not save',
      message: trimmed != null && trimmed.isNotEmpty
          ? trimmed
          : 'Check your connection and retry',
      accentColor: const Color(0xFFFF453A),
    );
  }

  factory HxToastItem.targetsUpdated({
    String title = 'Targets updated',
    required String message,
  }) {
    return HxToastItem(
      id: 'targets_updated_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.flag_rounded,
      title: title,
      message: message,
      accentColor: const Color(0xFF30D158),
    );
  }

  factory HxToastItem.entryMoved({
    required String itemName,
    required String targetLabel,
  }) {
    return HxToastItem(
      id: 'entry_moved_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.restaurant_rounded,
      title: 'Moved to $targetLabel',
      message: itemName,
      accentColor: const Color(0xFF30D158),
    );
  }

  factory HxToastItem.workoutSynced() {
    return HxToastItem(
      id: 'workout_synced_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.check_circle_rounded,
      title: 'Workout saved',
      message: 'Synced to Health Connect',
      accentColor: const Color(0xFF30D158),
    );
  }

  factory HxToastItem.workoutSyncFailed() {
    return HxToastItem(
      id: 'workout_sync_failed_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.error_rounded,
      title: 'Sync failed',
      message: 'Check Health Connect permissions in settings',
      accentColor: const Color(0xFFFF453A),
    );
  }

  factory HxToastItem.weightLogged({required String weightFormatted}) {
    return HxToastItem(
      id: 'weight_logged_${DateTime.now().microsecondsSinceEpoch}',
      icon: Icons.monitor_weight_rounded,
      title: 'Weight logged',
      message: weightFormatted,
      accentColor: const Color(0xFF4DA3FF),
    );
  }
}
