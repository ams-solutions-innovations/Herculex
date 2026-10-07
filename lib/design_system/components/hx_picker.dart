import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// One row in an [HxPicker] sheet.
class HxPickerOption<T> {
  const HxPickerOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.color,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;

  /// Accent for the icon and the selected check; defaults to the theme primary.
  final Color? color;
  final bool enabled;
}

/// A tappable pill showing the current choice; opens an [HxPicker] sheet.
class HxPickerPill extends StatelessWidget {
  const HxPickerPill({
    super.key,
    required this.caption,
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
  });

  /// Small uppercase caption above the value.
  final String caption;
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final accent = color ?? hx.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style: TextStyle(
                      color: hx.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hx.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet single-choice picker. Returns the chosen value, or null if
/// the sheet is dismissed.
Future<T?> showHxPicker<T>(
  BuildContext context, {
  required String title,
  required List<HxPickerOption<T>> options,
  required T selected,
  String? subtitle,
}) {
  return HxSheet.show<T>(
    context,
    builder: (ctx) => HxSheet(
      title: title,
      subtitle: subtitle,
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(HxSpace.x3, 0, HxSpace.x3, HxSpace.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            _HxPickerRow<T>(
              option: o,
              selected: o.value == selected,
              onTap: () {
                Haptics.selection();
                Navigator.of(ctx).pop(o.value);
              },
            ),
        ],
      ),
    ),
  );
}

class _HxPickerRow<T> extends StatelessWidget {
  const _HxPickerRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final HxPickerOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final accent = option.color ?? hx.primary;
    final enabled = option.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: selected ? accent.withValues(alpha: 0.12) : null,
        leading: option.icon == null
            ? null
            : Icon(option.icon, color: selected ? accent : hx.onSurfaceVariant),
        title: Text(
          option.label,
          style: TextStyle(
            color: selected ? accent : hx.onSurface,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: option.description == null
            ? null
            : Text(
                option.description!,
                style: TextStyle(color: hx.onSurfaceVariant, fontSize: 12),
              ),
        trailing: selected ? Icon(Icons.check_rounded, color: accent) : null,
      ),
    );
  }
}
