import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_style.dart';

class ChartLegendItem {
  const ChartLegendItem({required this.color, required this.label});
  final Color color;
  final String label;
}

/// Shared frame of the three progress charts: title, latest value, legend,
/// one-line summary and the empty state.
class PhysiqueChartCard extends StatelessWidget {
  const PhysiqueChartCard({
    super.key,
    required this.title,
    this.latestValue,
    this.header,
    required this.plot,
    required this.legend,
    required this.summary,
    this.caption,
    required this.emptyText,
    this.emptyIcon = Icons.show_chart_rounded,
  });

  final String title;
  final String? latestValue;
  final Widget? header;

  /// Null renders the empty state instead of a plot.
  final Widget? plot;
  final List<ChartLegendItem> legend;
  final String summary;
  final String? caption;
  final String emptyText;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final plot = this.plot;
    final latest = latestValue;
    return HxCard(
      padding: const EdgeInsets.all(HxSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: PhysiqueText.heading(context, color: hx.onSurface),
                ),
              ),
              if (latest != null) ...[
                const SizedBox(width: HxSpace.x2),
                Text(
                  latest,
                  style: PhysiqueText.display(context, color: hx.onSurface),
                ),
              ],
            ],
          ),
          if (header != null) ...[const SizedBox(height: HxSpace.x3), header!],
          const SizedBox(height: HxSpace.x4),
          if (plot != null)
            SizedBox(
              height: PhysiqueChartStyle.plotHeight,
              child: Semantics(
                label: summary,
                excludeSemantics: true,
                child: plot,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: PhysiqueChartStyle.plotHeight,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(emptyIcon, size: 32, color: hx.tertiary),
                    const SizedBox(height: HxSpace.x2),
                    Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: PhysiqueText.body(
                        context,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (legend.isNotEmpty && plot != null) ...[
            const SizedBox(height: HxSpace.x3),
            Wrap(
              spacing: HxSpace.x4,
              runSpacing: HxSpace.x2,
              children: [for (final item in legend) _LegendEntry(item: item)],
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: HxSpace.x2),
            Text(
              caption!,
              style: PhysiqueText.label(context, color: hx.secondary),
            ),
          ],
          const SizedBox(height: HxSpace.x2),
          Text(
            summary,
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.item});
  final ChartLegendItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: HxRadius.pillAll,
          ),
        ),
        const SizedBox(width: HxSpace.x2),
        Text(
          item.label,
          style: PhysiqueText.label(context, color: context.hx.secondary),
        ),
      ],
    );
  }
}
