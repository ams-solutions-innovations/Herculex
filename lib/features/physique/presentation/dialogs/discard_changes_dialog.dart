import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Asks before throwing away unsaved roadmap edits.
abstract final class DiscardChangesDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.danger,
              foregroundColor: context.hx.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
  }
}
