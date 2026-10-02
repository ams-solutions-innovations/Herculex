import 'package:flutter/material.dart';

/// Confirms archiving the current goal before a new one starts (D-03).
/// Nothing is deleted, so the confirm button is primary, not destructive.
abstract final class StartNewGoalDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new goal?'),
        content: const Text(
          'Your current goal, check-ins and photos move to Past goals. You '
          'can still view them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep current goal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start new goal'),
          ),
        ],
      ),
    );
  }
}
