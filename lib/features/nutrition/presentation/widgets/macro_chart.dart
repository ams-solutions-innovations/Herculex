import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/colors.dart';
import '../../domain/daily_totals.dart';
import '../../domain/macro_targets.dart';

/// Shared macro-trend helpers, extracted from the dashboard's LiveMacrosGrid
/// so the weekly-calories stats page and future trend surfaces render the
/// exact same chart. Macro keys: 'kcal', 'protein', 'carbs', 'fat'.
int macroDaysForRange(String range) {
  return switch (range) {
    '3D' => 3,
    '7D' => 7,
    '14D' => 14,
    '30D' => 30,
    '90D' => 90,
    _ => 7,
  };
}

Color macroColorFor(String macro) {
  return switch (macro) {
    'kcal' => AppColors.macroKcal,
    'protein' => AppColors.macroProtein,
    'carbs' => AppColors.macroCarbs,
    'fat' => AppColors.macroFat,
    _ => AppColors.macroKcal,
  };
}

String macroUnitFor(String macro) => macro == 'kcal' ? 'kcal' : 'g';

double? macroTargetFor(MacroTargets? t, String macro) {
  if (t == null) return null;
  return switch (macro) {
    'kcal' => t.kcal.toDouble(),
    'protein' => t.proteinG.toDouble(),
    'carbs' => t.carbsG.toDouble(),
    'fat' => t.fatG.toDouble(),
    _ => null,
  };
}

double macroValueForTotals(DailyTotals totals, String macro) {
  return switch (macro) {
    'kcal' => totals.kcal,
    'protein' => totals.proteinG,
    'carbs' => totals.carbsG,
    'fat' => totals.fatG,
    _ => totals.kcal,
  };
}

/// Line chart of one macro over the trailing [range], with an optional dashed
/// target line. Days missing from [historyMap] render as zero.
class MacroTrendChart extends StatelessWidget {
  const MacroTrendChart({
    super.key,
    required this.historyMap,
    required this.macro,
    required this.range,
    this.targetValue,
    this.height = 160,
  });

  final Map<String, DailyTotals> historyMap;
  final String macro;
  final String range;
  final double? targetValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = macroDaysForRange(range);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final color = macroColorFor(macro);
    final unit = macroUnitFor(macro);
    final targetValue = this.targetValue;

    final spots = <FlSpot>[];
    final dates = <DateTime>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      dates.add(date);
      final iso = DateFormat('yyyy-MM-dd').format(date);
      final totals = historyMap[iso] ?? DailyTotals.empty;
      final val = macroValueForTotals(totals, macro);
      spots.add(FlSpot((days - 1 - i).toDouble(), val));
    }

    final hasAnyData = spots.any((s) => s.y > 0);

    if (!hasAnyData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No logged nutrition entries in the selected timeframe.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.secondary),
          ),
        ),
      );
    }

    final maxYValue = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final topBound = (targetValue != null && targetValue > maxYValue)
        ? targetValue * 1.15
        : maxYValue > 0
            ? maxYValue * 1.2
            : 100.0;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days - 1).toDouble(),
          minY: 0,
          maxY: topBound,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: topBound / 4 > 0 ? topBound / 4 : 1,
            getDrawingHorizontalLine: (val) => FlLine(
              color: AppColors.outlineVariant.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (days / 4).clamp(1.0, 30.0),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dates.length) return const SizedBox.shrink();
                  final d = dates[idx];
                  final label = days <= 7
                      ? DateFormat('E').format(d)
                      : DateFormat('M/d').format(d);
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: targetValue == null || targetValue <= 0
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: targetValue,
                      color: color.withValues(alpha: 0.5),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 8, bottom: 2),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (_) =>
                            'Target: ${targetValue.round()} $unit',
                      ),
                    ),
                  ],
                ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final dateStr = idx >= 0 && idx < dates.length
                      ? DateFormat('MMM d').format(dates[idx])
                      : '';
                  return LineTooltipItem(
                    '$dateStr\n${spot.y.round()} $unit',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: days <= 14,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
