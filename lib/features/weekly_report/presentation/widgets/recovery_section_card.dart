import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Recovery, sleep and activity card of the weekly report.
///
/// Relationship sentences are rendered verbatim from the stored
/// [CorrelationLine.statement]; this card never builds its own causal text
/// (RPT-05, D-12).
class RecoverySectionCard extends StatelessWidget {
  const RecoverySectionCard({super.key, required this.section});

  final RecoverySection? section;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final s = section;
    return SectionCardScaffold(
      title: 'Recovery',
      icon: Icons.bedtime_outlined,
      accent: hx.domainRecovery,
      body: s == null ? null : _Body(section: s, accent: hx.domainRecovery),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.section, required this.accent});

  final RecoverySection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final sleep = section.avgSleepHours;
    final steps = section.avgSteps;
    final hr = section.avgRestingHr;
    final tiles = <Widget>[
      if (sleep != null)
        HxStatTile(
          label: 'Avg sleep',
          value: '${sleep.toStringAsFixed(1)} h',
          icon: Icons.bedtime_outlined,
          accent: accent,
        ),
      if (steps != null)
        HxStatTile(
          label: 'Avg steps',
          value: '$steps',
          icon: Icons.directions_walk_outlined,
          accent: accent,
        ),
      if (hr != null)
        HxStatTile(
          label: 'Resting HR',
          value: '${hr.round()} bpm',
          icon: Icons.favorite_outline,
          accent: accent,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tiles.isNotEmpty) ReportTileGrid(tiles: tiles),
        if (section.recoveryWarnings.isNotEmpty) ...[
          const SizedBox(height: HxSpace.x4),
          for (final warning in section.recoveryWarnings)
            Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x1),
              child: Text(warning, style: ReportText.body(context)),
            ),
        ],
        if (section.cnsDeloadSuggested) ...[
          const SizedBox(height: HxSpace.x2),
          Text(
            'Deload suggested',
            style: ReportText.body(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        if (section.correlations.isNotEmpty) ...[
          const SizedBox(height: HxSpace.x4),
          for (final line in section.correlations)
            Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x2),
              child: Text(line.statement, style: ReportText.body(context)),
            ),
        ],
      ],
    );
  }
}
