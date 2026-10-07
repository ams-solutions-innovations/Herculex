import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Nutrition card of the weekly report. Renders only the frozen
/// [NutritionSection]; a null section shows the no-data line (RPT-01, D-06).
class NutritionSectionCard extends StatelessWidget {
  const NutritionSectionCard({super.key, required this.section});

  final NutritionSection? section;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final s = section;
    return SectionCardScaffold(
      title: 'Nutrition',
      icon: Icons.restaurant_outlined,
      accent: hx.domainNutrition,
      body: s == null ? null : _Body(section: s, accent: hx.domainNutrition),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.section, required this.accent});

  final NutritionSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final targetKcal = section.targetKcal;
    final targetProtein = section.targetProteinG;
    final adherence = section.adherenceDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportTileGrid(
          tiles: [
            HxStatTile(
              label: 'Avg calories',
              value: '${section.avgKcal}',
              secondaryValue: targetKcal == null ? null : 'of $targetKcal',
              icon: Icons.local_fire_department_outlined,
              accent: accent,
            ),
            HxStatTile(
              label: 'Avg protein',
              value: '${section.avgProteinG} g',
              secondaryValue: targetProtein == null
                  ? null
                  : 'of $targetProtein g',
              icon: Icons.egg_alt_outlined,
              accent: accent,
            ),
            HxStatTile(
              label: 'Days logged',
              value: '${section.daysLogged}',
              icon: Icons.event_available_outlined,
              accent: accent,
            ),
            if (adherence != null)
              HxStatTile(
                label: 'Days on target',
                value: '$adherence',
                icon: Icons.flag_outlined,
                accent: accent,
              ),
          ],
        ),
        if (section.topFoods.isNotEmpty) ...[
          const SizedBox(height: HxSpace.x4),
          Text('Most logged', style: ReportText.label(context)),
          const SizedBox(height: HxSpace.x2),
          for (final food in section.topFoods)
            Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(food.name, style: ReportText.body(context)),
                  ),
                  const SizedBox(width: HxSpace.x2),
                  Text('x${food.count}', style: ReportText.label(context)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
