import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Colour, icon and word for each verdict. Off track uses the warning token (UI-SPEC rule 6).
abstract final class VerdictStyle {
  static String label(CheckInVerdict v) => switch (v) {
    CheckInVerdict.onTrack => 'On track',
    CheckInVerdict.offTrack => 'Off track',
    CheckInVerdict.inconclusive => 'Inconclusive',
  };

  static IconData icon(CheckInVerdict v) => switch (v) {
    CheckInVerdict.onTrack => Icons.trending_up_rounded,
    CheckInVerdict.offTrack => Icons.trending_flat_rounded,
    CheckInVerdict.inconclusive => Icons.help_outline_rounded,
  };

  static Color color(HxColors hx, CheckInVerdict v) => switch (v) {
    CheckInVerdict.onTrack => hx.success,
    CheckInVerdict.offTrack => hx.warning,
    CheckInVerdict.inconclusive => hx.secondary,
  };
}

/// Non-interactive three-state chip: icon + word + state colour.
class VerdictChip extends StatelessWidget {
  const VerdictChip({super.key, required this.verdict});

  final CheckInVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final color = VerdictStyle.color(hx, verdict);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HxSpace.x4,
        vertical: HxSpace.x2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: HxRadius.pillAll,
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(VerdictStyle.icon(verdict), size: 18, color: color),
          const SizedBox(width: HxSpace.x1),
          Flexible(
            child: Text(
              VerdictStyle.label(verdict),
              style: PhysiqueText.labelStrong(context, color: hx.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
