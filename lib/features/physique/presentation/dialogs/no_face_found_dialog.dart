import 'package:flutter/material.dart';

enum NoFaceChoice { retake, saveWithoutBlur }

/// Shown when blur was requested but no face was found. Never claims the
/// photo was blurred (D-07).
abstract final class NoFaceFoundDialog {
  static Future<NoFaceChoice?> show(BuildContext context) {
    return showDialog<NoFaceChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No face found'),
        content: const Text(
          "We couldn't find a face to blur, so this photo isn't blurred. Save "
          'it as is, or retake it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(NoFaceChoice.retake),
            child: const Text('Retake photo'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(NoFaceChoice.saveWithoutBlur),
            child: const Text('Save without blur'),
          ),
        ],
      ),
    );
  }
}
