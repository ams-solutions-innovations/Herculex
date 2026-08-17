import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/tokens/tokens.dart';

/// Fully-rounded capsule used for compact rows, tags and filter chips.
///
/// [selected] switches to the accent-tinted treatment, so filter rows do not
/// each invent their own selected style.
class HxPill extends StatelessWidget {
  const HxPill({
    super.key,
    required this.child,
    this.onTap,
    this.padding =
        const EdgeInsets.symmetric(horizontal: HxSpace.x4, vertical: HxSpace.x2),
    this.selected = false,
    this.accent,
    this.fill,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;

  /// Defaults to the brand color; pass a domain color to code the pill.
  final Color? accent;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final accent = this.accent ?? hx.primary;

    final pill = AnimatedContainer(
      duration: HxMotion.fast,
      curve: HxMotion.standard,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ??
            (selected
                ? accent.withValues(alpha: 0.15)
                : hx.surfaceContainerLowest),
        borderRadius: HxRadius.pillAll,
        border: Border.all(
          color: selected
              ? accent
              : hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: selected ? accent : hx.secondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        child: child,
      ),
    );

    if (onTap == null) return pill;

    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap!();
      },
      borderRadius: HxRadius.pillAll,
      child: pill,
    );
  }
}

/// Text-only convenience wrapper — the overwhelmingly common case.
class HxTextPill extends StatelessWidget {
  const HxTextPill({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.accent,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return HxPill(
      onTap: onTap,
      selected: selected,
      accent: accent,
      padding: const EdgeInsets.symmetric(
          horizontal: HxSpace.x3, vertical: HxSpace.x1 + 2),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
