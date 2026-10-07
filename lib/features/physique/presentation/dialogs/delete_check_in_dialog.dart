import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Confirms deleting a check-in. The weekly slot stays used (PHYS-06).
abstract final class DeleteCheckInDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this check-in?'),
        content: const Text(
          'The photo is removed from your device. Your next check-in date '
          "won't change.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep check-in'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.danger,
              foregroundColor: context.hx.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete check-in'),
          ),
        ],
      ),
    );
  }
}
