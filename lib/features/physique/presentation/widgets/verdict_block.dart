import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/confidence_range_bar.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_chip.dart';

final _percentNumber = RegExp(
  r'\d+(?:[.,]\d+)?\s*(?:%|percent|per\s*cent)',
  caseSensitive: false,
);

/// Defence in depth for D-11, same rule as the check-in service.
String _withoutPercent(String raw) => raw
    .replaceAll(_percentNumber, '')
    .replaceAll('%', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Chip, range bar and one reason line (D-11, PHYS-07). Never renders a
/// percentage and never navigates; callers supply the callbacks.
class VerdictBlock extends StatelessWidget {
  const VerdictBlock({
    super.key,
    required this.verdict,
    required this.band,
    required this.confidence,
    required this.reason,
    this.onReviewTargets,
    this.onLogMeasurements,
  });

  final CheckInVerdict verdict;
  final CheckInBand? band;
  final AssessmentConfidence confidence;
  final String reason;
  final VoidCallback? onReviewTargets;
  final VoidCallback? onLogMeasurements;

  bool get _lowConfidence =>
      confidence == AssessmentConfidence.low ||
      confidence == AssessmentConfidence.unknown;

  String get _confidenceWord => switch (confidence) {
    AssessmentConfidence.high => 'High',
    AssessmentConfidence.medium => 'Medium',
    _ => 'Low',
  };

  String _semanticsLabel(String cleanReason) {
    final b = band;
    final head = 'Check-in verdict: ${VerdictStyle.label(verdict)}.';
    final lean = b == null
        ? ''
        : ' Direction estimate leans '
              '${(b.low + b.high) / 2 >= 0 ? 'toward' : 'away from'} your goal, '
              '${_confidenceWord.toLowerCase()} confidence.';
    return '$head$lean $cleanReason'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final clean = _withoutPercent(reason);
    final color = VerdictStyle.color(hx, verdict);
    final showReview =
        verdict != CheckInVerdict.onTrack && onReviewTargets != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: _semanticsLabel(clean),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VerdictChip(verdict: verdict),
                if (band != null) ...[
                  const SizedBox(height: HxSpace.x4),
                  ConfidenceRangeBar(band: band!, color: color),
                ],
                if (clean.isNotEmpty) ...[
                  const SizedBox(height: HxSpace.x4),
                  Text(
                    clean,
                    style: PhysiqueText.body(context, color: hx.onSurface),
                  ),
                ],
                const SizedBox(height: HxSpace.x1),
                Text(
                  'Confidence: $_confidenceWord',
                  style: PhysiqueText.label(context, color: hx.secondary),
                ),
                const SizedBox(height: HxSpace.x1),
                Text(
                  'An estimate from your photos, not a measurement.',
                  style: PhysiqueText.label(context, color: hx.secondary),
                ),
              ],
            ),
          ),
        ),
        if (_lowConfidence && onLogMeasurements != null)
          TextButton(
            onPressed: onLogMeasurements,
            child: const Text('Log measurements to refine this.'),
          ),
        if (showReview)
          TextButton(
            onPressed: onReviewTargets,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text('Review nutrition targets')),
                SizedBox(width: HxSpace.x1),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
