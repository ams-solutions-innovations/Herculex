import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Shared fl_chart styling for the three physique charts (UI-SPEC Charts).
abstract final class PhysiqueChartStyle {
  /// Height of the plot area; the only fixed height in a chart card.
  static const double plotHeight = 200;

  static FlBorderData get noBorder => FlBorderData(show: false);

  static FlGridData grid(BuildContext context, {double? horizontalInterval}) {
    final hx = context.hx;
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: horizontalInterval,
      getDrawingHorizontalLine: (_) => FlLine(
        color: hx.outlineVariant.withValues(alpha: 0.5),
        strokeWidth: 1,
      ),
    );
  }

  /// At most four labels per axis; text is `label` in `secondary`.
  static FlTitlesData titles(
    BuildContext context, {
    required String Function(double) leftLabel,
    required String Function(double) bottomLabel,
    required double leftInterval,
    required double bottomInterval,
    double leftReserved = 44,
  }) {
    final style = PhysiqueText.label(context, color: context.hx.secondary);
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: leftReserved,
          interval: leftInterval,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(leftLabel(value), style: style),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(bottomLabel(value), style: style),
          ),
        ),
      ),
    );
  }

  /// [format] returns the tooltip line for a spot, or null to hide it.
  static LineTouchData touch(
    BuildContext context, {
    required String? Function(LineBarSpot) format,
  }) {
    final hx = context.hx;
    final style = PhysiqueText.bodyStrong(context, color: hx.onSurface);
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => hx.surfaceContainer,
        getTooltipItems: (spots) => [
          for (final s in spots)
            () {
              final text = format(s);
              return text == null ? null : LineTooltipItem(text, style);
            }(),
        ],
      ),
    );
  }

  /// Only the final spot gets a dot: radius 4, 2px lowest-surface ring.
  static FlDotData lastPointDot(BuildContext context, {required Color color}) {
    final ring = context.hx.surfaceContainerLowest;
    return FlDotData(
      show: true,
      checkToShowDot: (spot, bar) =>
          bar.spots.isNotEmpty && spot == bar.spots.last,
      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
        radius: 4,
        color: color,
        strokeWidth: 2,
        strokeColor: ring,
      ),
    );
  }

  static Duration animationDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : HxMotion.slow;

  /// Dashed 1px vertical lines, no labels.
  static ExtraLinesData phaseBoundaries(BuildContext context, List<double> xs) {
    final outline = context.hx.outline;
    return ExtraLinesData(
      extraLinesOnTop: false,
      verticalLines: [
        for (final x in xs)
          VerticalLine(
            x: x,
            color: outline,
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
      ],
    );
  }

  /// "3 months" style period for the one-line summaries.
  static String periodLabel(ChartRange range, int spanDays) {
    switch (range) {
      case ChartRange.month:
        return '1 month';
      case ChartRange.quarter:
        return '3 months';
      case ChartRange.all:
        final months = (spanDays / 30).round();
        if (months >= 1) return months == 1 ? '1 month' : '$months months';
        final weeks = (spanDays / 7).round().clamp(1, 4);
        return weeks == 1 ? '1 week' : '$weeks weeks';
    }
  }

  /// Round to one decimal and drop a trailing ".0".
  static String kg(double value) {
    final s = value.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}
