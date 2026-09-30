import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/design_system/tokens/hx_geometry.dart';

/// Presentational banner shown when Herculex AI's suggested program design
/// brief could not be used (Phase 27, D-05) — a rejected/unparseable brief,
/// or an offline/unconfigured/over-quota degradation (AIP-05).
///
/// [heading], [body] and [footer] are always passed in by the caller and
/// rendered verbatim; this widget never derives or hardcodes their content,
/// so plan 27-11 can reuse it for every distinct rejection/degradation
/// message the flow needs. Visually a sibling of `EmptySlotNotice` (same
/// `Container`/`Row`/icon/`Expanded(Text)` shape) but not a reuse of it —
/// `EmptySlotNotice` is documented as rendering only the planner's own
/// empty-slot text.
class AiBriefRejectionBanner extends StatelessWidget {
  const AiBriefRejectionBanner({
    super.key,
    required this.heading,
    required this.body,
    required this.footer,
  });

  final String heading;
  final String body;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Semantics(
      label: heading,
      child: Container(
        padding: const EdgeInsets.all(HxSpace.x3),
        decoration: BoxDecoration(
          color: hx.warning.withValues(alpha: .08),
          borderRadius: HxRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: hx.warning,
                ),
                const SizedBox(width: HxSpace.x2),
                Expanded(
                  child: Text(
                    heading,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: hx.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HxSpace.x2),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: HxSpace.x1),
            Text(
              footer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hx.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
