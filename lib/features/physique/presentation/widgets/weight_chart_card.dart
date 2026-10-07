import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_card_frame.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_style.dart';
import 'package:intl/intl.dart';

/// Bodyweight trend with raw weigh-ins and the moving phase-target band.
class WeightChartCard extends ConsumerWidget {
  const WeightChartCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(physiqueWeightChartProvider(goalId));
    final hx = context.hx;
    final trend = data.trend;
    final latest = trend.isEmpty
        ? null
        : '${trend.last.value.toStringAsFixed(1)} kg';

    return PhysiqueChartCard(
      title: 'Bodyweight',
      latestValue: latest,
      plot: trend.length < 2 ? null : _WeightPlot(data: data),
      legend: [
        ChartLegendItem(color: hx.onSurface, label: 'Trend'),
        if (data.bands.isNotEmpty)
          ChartLegendItem(
            color: hx.domainNutrition.withValues(alpha: 0.14),
            label: 'Target range',
          )
        else
          ChartLegendItem(color: hx.secondary, label: 'Weigh-ins'),
      ],
      summary: data.textSummary,
      emptyText: 'Log your weight to see your trend.',
    );
  }
}

class _WeightPlot extends StatelessWidget {
  const _WeightPlot({required this.data});

  final WeightChartData data;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final origin = data.trend.first.date;
    final originDay = TrendSeries.dayNumber(origin);
    double xOf(DateTime d) => (TrendSeries.dayNumber(d) - originDay).toDouble();
    final maxX = xOf(data.trend.last.date);

    final trendSpots = [
      for (final p in data.trend) FlSpot(xOf(p.date), p.value),
    ];
    final rawSpots = [
      for (final p in data.raw)
        if (xOf(p.date) >= 0) FlSpot(xOf(p.date), p.value),
    ];

    // Band edges clipped to the visible x range by linear interpolation.
    final bandBars = <LineChartBarData>[];
    final bands = <BetweenBarsData>[];
    final boundaries = <double>[];
    var minY = trendSpots.map((s) => s.y).reduce(math.min);
    var maxY = trendSpots.map((s) => s.y).reduce(math.max);
    for (final s in rawSpots) {
      minY = math.min(minY, s.y);
      maxY = math.max(maxY, s.y);
    }
    for (final b in data.bands) {
      final x0 = xOf(b.start);
      final x1 = xOf(b.end);
      if (x1 <= 0 || x0 >= maxX || x1 <= x0) continue;
      double at(double x, double a, double z) =>
          a + (z - a) * ((x - x0) / (x1 - x0));
      final cx0 = math.max(x0, 0.0);
      final cx1 = math.min(x1, maxX);
      final lowStart = at(cx0, b.startLowKg, b.endLowKg);
      final lowEnd = at(cx1, b.startLowKg, b.endLowKg);
      final highStart = at(cx0, b.startHighKg, b.endHighKg);
      final highEnd = at(cx1, b.startHighKg, b.endHighKg);
      minY = math.min(minY, math.min(lowStart, lowEnd));
      maxY = math.max(maxY, math.max(highStart, highEnd));
      if (x0 > 0) boundaries.add(x0);
      final from = 2 + bandBars.length;
      bandBars
        ..add(
          _invisible(hx.onSurface.withValues(alpha: 0), [
            FlSpot(cx0, lowStart),
            FlSpot(cx1, lowEnd),
          ]),
        )
        ..add(
          _invisible(hx.onSurface.withValues(alpha: 0), [
            FlSpot(cx0, highStart),
            FlSpot(cx1, highEnd),
          ]),
        );
      bands.add(
        BetweenBarsData(
          fromIndex: from,
          toIndex: from + 1,
          color: hx.domainNutrition.withValues(alpha: 0.14),
        ),
      );
    }
    minY = (minY - 1).floorToDouble();
    maxY = (maxY + 1).ceilToDouble();
    final leftInterval = math.max(1.0, ((maxY - minY) / 3).ceilToDouble());
    final bottomInterval = math.max(1.0, (maxX / 3).ceilToDouble());
    final fmt = DateFormat('MMM d');

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: PhysiqueChartStyle.grid(
          context,
          horizontalInterval: leftInterval,
        ),
        borderData: PhysiqueChartStyle.noBorder,
        titlesData: PhysiqueChartStyle.titles(
          context,
          leftInterval: leftInterval,
          bottomInterval: bottomInterval,
          leftLabel: (v) => v.toStringAsFixed(0),
          bottomLabel: (v) => fmt.format(
            DateTime(origin.year, origin.month, origin.day + v.round()),
          ),
        ),
        extraLinesData: PhysiqueChartStyle.phaseBoundaries(context, boundaries),
        betweenBarsData: bands,
        lineTouchData: PhysiqueChartStyle.touch(
          context,
          format: (s) => s.barIndex == 0
              ? '${fmt.format(DateTime(origin.year, origin.month, origin.day + s.x.round()))}: ${s.y.toStringAsFixed(1)} kg'
              : null,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: trendSpots,
            isCurved: true,
            color: hx.onSurface,
            barWidth: 2.5,
            dotData: PhysiqueChartStyle.lastPointDot(
              context,
              color: hx.onSurface,
            ),
          ),
          LineChartBarData(
            spots: rawSpots,
            color: hx.onSurface.withValues(alpha: 0),
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2,
                color: hx.secondary,
                strokeWidth: 0,
              ),
            ),
          ),
          ...bandBars,
        ],
      ),
      duration: PhysiqueChartStyle.animationDuration(context),
    );
  }

  LineChartBarData _invisible(Color hidden, List<FlSpot> spots) =>
      LineChartBarData(
        spots: spots,
        color: hidden,
        barWidth: 0,
        dotData: const FlDotData(show: false),
      );
}
