import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/design_system/tokens/hx_geometry.dart';

/// Presentational card rendering Herculex AI's per-day rationale
/// (`ProgramBrief.dayRoles[].rationale`, AIP-04/D-09) in the program review
/// screen, alongside — never replacing — any existing per-slot
/// `EmptySlotNotice`/`SelectionExplanation` rationale in the same day card.
///
/// [rationale] is always rendered verbatim, with no truncation, ellipsis or
/// re-derivation, mirroring `EmptySlotNotice`'s own non-negotiable rule for
/// its `reason` field. Visually a sibling of `EmptySlotNotice` (same
/// `Container`/`Row`/icon/`Expanded(Text)` shape) but not a reuse of it.
class AiDayRationaleCard extends StatelessWidget {
  const AiDayRationaleCard({super.key, required this.rationale});

  final String rationale;

  static const String _heading = 'Why this day';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Semantics(
      label: _heading,
      child: Container(
        padding: const EdgeInsets.all(HxSpace.x4),
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: HxRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: hx.primary,
                ),
                const SizedBox(width: HxSpace.x2),
                Expanded(
                  child: Text(
                    _heading,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: hx.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HxSpace.x2),
            Text(rationale, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
