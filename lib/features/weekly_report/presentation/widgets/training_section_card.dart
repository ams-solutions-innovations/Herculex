import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Training card of the weekly report. Renders only the frozen
/// [TrainingSection]; a null section shows the no-data line (RPT-01, D-06).
class TrainingSectionCard extends StatelessWidget {
  const TrainingSectionCard({super.key, required this.section});

  final TrainingSection? section;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final s = section;
    return SectionCardScaffold(
      title: 'Training',
      icon: Icons.fitness_center,
      accent: hx.domainTraining,
      body: s == null ? null : _Body(section: s, accent: hx.domainTraining),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.section, required this.accent});

  final TrainingSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final prev = section.prevWeekTonnageKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportTileGrid(
          tiles: [
            HxStatTile(
              label: 'Sessions',
              value: '${section.sessions}',
              icon: Icons.event_repeat_outlined,
              accent: accent,
            ),
            HxStatTile(
              label: 'Tonnage',
              value: '${section.tonnageKg.toStringAsFixed(0)} kg',
              secondaryValue: prev == null
                  ? null
                  : '${signedNumber(section.tonnageKg - prev, fractionDigits: 0)}'
                        ' kg vs last week',
              icon: Icons.scale_outlined,
              accent: accent,
            ),
          ],
        ),
        if (section.e1rmMovers.isNotEmpty) ...[
          const SizedBox(height: HxSpace.x4),
          Text('Estimated 1RM movers', style: ReportText.label(context)),
          const SizedBox(height: HxSpace.x2),
          for (final mover in section.e1rmMovers)
            Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      mover.exerciseName,
                      style: ReportText.body(context),
                    ),
                  ),
                  const SizedBox(width: HxSpace.x2),
                  Text(
                    '${signedNumber(mover.deltaKg)} kg',
                    style: ReportText.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
