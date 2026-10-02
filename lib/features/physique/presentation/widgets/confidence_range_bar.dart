import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Shows the AI's directional band on a [-1, 1] track with a centre tick for
/// "no change". A wide segment is the uncertainty message; there are no
/// numbers (D-11).
class ConfidenceRangeBar extends StatelessWidget {
  const ConfidenceRangeBar({
    super.key,
    required this.band,
    required this.color,
  });

  static const segmentKey = Key('confidence-range-segment');
  static const double height = 12;
  static const double minSegmentWidth = 12;

  final CheckInBand band;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final center = w / 2;
              final start = (band.low + 1) / 2 * w;
              final end = (band.high + 1) / 2 * w;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: reduce ? 1 : 0, end: 1),
                duration: reduce ? Duration.zero : HxMotion.slow,
                curve: HxMotion.emphasized,
                builder: (context, t, _) {
                  var left = center + (start - center) * t;
                  var right = center + (end - center) * t;
                  if (right - left < minSegmentWidth) {
                    final mid = (left + right) / 2;
                    left = mid - minSegmentWidth / 2;
                    right = mid + minSegmentWidth / 2;
                  }
                  left = math.max(0, left);
                  right = math.min(w, math.max(right, left));
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: hx.surfaceVariant,
                            borderRadius: HxRadius.pillAll,
                          ),
                        ),
                      ),
                      Positioned(
                        left: left,
                        width: right - left,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          key: segmentKey,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: HxRadius.pillAll,
                          ),
                        ),
                      ),
                      Positioned(
                        left: center - 1,
                        width: 2,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(color: hx.outline),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: HxSpace.x1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Away from goal',
                style: PhysiqueText.label(context, color: hx.secondary),
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Flexible(
              child: Text(
                'Toward goal',
                textAlign: TextAlign.end,
                style: PhysiqueText.label(context, color: hx.secondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
