import 'package:flutter/material.dart';

/// Confirms replacing the user's roadmap edits with the suggested plan.
abstract final class ResetRoadmapDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset your roadmap?'),
        content: const Text(
          'Your edits will be replaced by the suggested plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset roadmap'),
          ),
        ],
      ),
    );
  }
}
