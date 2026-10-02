import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

abstract final class PhaseTypeIcon {
  static IconData of(DietPhase phase) => switch (phase) {
    DietPhase.cut => Icons.trending_down_rounded,
    DietPhase.bulk => Icons.trending_up_rounded,
    DietPhase.maintain => Icons.drag_handle_rounded,
    DietPhase.recomp => Icons.swap_vert_rounded,
    DietPhase.maingain => Icons.north_east_rounded,
  };
}

/// Icon + label pill for a [DietPhase]. Disabled when [onTap] is null.
class PhaseTypePill extends StatelessWidget {
  const PhaseTypePill({
    super.key,
    required this.phase,
    this.selected = false,
    this.onTap,
  });

  final DietPhase phase;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final enabled = onTap != null;
    final color = enabled
        ? (selected ? hx.primaryText : hx.secondary)
        : hx.tertiary;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: phase.label,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          widthFactor: 1,
          child: HxPill(
            selected: selected && enabled,
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhaseTypeIcon.of(phase), size: 18, color: color),
                const SizedBox(width: HxSpace.x1),
                Flexible(
                  child: Text(
                    phase.label,
                    style: PhysiqueText.labelStrong(context, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
