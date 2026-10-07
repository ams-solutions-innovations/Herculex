import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Offers the "Blur my face" choice before any baseline photo is stored
/// (D-07). Returns the chosen flag, or null when the user cancels.
abstract final class BaselinePrivacyDialog {
  static Future<bool?> show(BuildContext context, {required bool initialBlur}) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        var blur = initialBlur;
        return StatefulBuilder(
          builder: (context, setState) {
            final hx = context.hx;
            return AlertDialog(
              title: const Text('Photo privacy'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: blur,
                    onChanged: (v) => setState(() => blur = v),
                    title: Text(
                      'Blur my face',
                      style: PhysiqueText.bodyStrong(context),
                    ),
                    subtitle: Text(
                      'Happens on your device. The original face is never '
                      'saved.',
                      style: PhysiqueText.label(
                        context,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: HxSpace.x3),
                  Text(
                    'Location and camera details are removed from every '
                    'photo.',
                    style: PhysiqueText.label(context, color: hx.secondary),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(blur),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
