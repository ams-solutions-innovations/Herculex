import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Physique card of the weekly report: the newest check-in verdict and the
/// bodyweight movement. Neutral tint, since physique has no domain colour.
///
/// A section whose fields are all empty is treated like a null section.
class PhysiqueSectionCard extends StatelessWidget {
  const PhysiqueSectionCard({super.key, required this.section});

  final PhysiqueSection? section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    return SectionCardScaffold(
      title: 'Physique',
      icon: Icons.accessibility_new_outlined,
      body: s != null && (s.checkInVerdict != null || s.bodyweightKg != null)
          ? _Body(section: s, accent: context.hx.secondary)
          : null,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.section, required this.accent});

  final PhysiqueSection section;
  final Color accent;

  /// Plain-words verdict. An unknown wire value reads as inconclusive rather
  /// than leaking the raw string.
  static String _verdictWords(String wire) => switch (wire) {
    'on_track' => 'On track',
    'off_track' => 'Off track',
    _ => 'Inconclusive',
  };

  @override
  Widget build(BuildContext context) {
    final verdict = section.checkInVerdict;
    final confidence = section.checkInConfidence;
    final weight = section.bodyweightKg;
    final delta = section.bodyweightDeltaKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportTileGrid(
          tiles: [
            if (verdict != null)
              HxStatTile(
                label: 'Latest check-in',
                value: _verdictWords(verdict),
                icon: Icons.fact_check_outlined,
                accent: accent,
              ),
            if (weight != null)
              HxStatTile(
                label: 'Bodyweight',
                value: '${weight.toStringAsFixed(1)} kg',
                secondaryValue: delta == null
                    ? null
                    : '${signedNumber(delta)} kg',
                icon: Icons.monitor_weight_outlined,
                accent: accent,
              ),
          ],
        ),
        if (verdict != null && confidence != null) ...[
          const SizedBox(height: HxSpace.x2),
          Text('Confidence: $confidence', style: ReportText.label(context)),
        ],
      ],
    );
  }
}
