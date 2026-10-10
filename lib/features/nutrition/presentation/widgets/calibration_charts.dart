import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_calibration_series.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_card_frame.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_style.dart';
import 'package:intl/intl.dart';

final NumberFormat _ints = NumberFormat('#,##0');

/// Dot colour per estimate method, shared by the trend chart and its legend.
Color calibrationMethodColor(HxColors hx, TdeeMethod method) =>
    switch (method) {
      TdeeMethod.observed => hx.success,
      TdeeMethod.classifier => hx.primary,
      TdeeMethod.coldStart => hx.onSurfaceVariant,
    };

/// A rounded axis range around [lo]..[hi] with at least [minSpan] of height.
({double min, double max}) _range(double lo, double hi, double minSpan) {
  final pad = math.max((hi - lo) * 0.15, minSpan / 2);
  final mid = (hi + lo) / 2;
  final half = math.max((hi - lo) / 2 + pad, minSpan / 2);
  return (min: mid - half, max: mid + half);
}

// ── Estimate history ─────────────────────────────────────────────────────────

/// Maintenance estimate over time, one dot per recalibration, coloured by how
/// that estimate was reached.
class EstimateHistoryChart extends StatelessWidget {
  const EstimateHistoryChart({super.key, required this.history});

  /// Newest first, as the repository returns it.
  final List<TdeeEstimateResult> history;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final points = history.reversed.toList(growable: false);
    final legend = [
      ChartLegendItem(
        color: calibrationMethodColor(hx, TdeeMethod.coldStart),
        label: 'Starting estimate',
      ),
      ChartLegendItem(
        color: calibrationMethodColor(hx, TdeeMethod.classifier),
        label: 'Classified',
      ),
      ChartLegendItem(
        color: calibrationMethodColor(hx, TdeeMethod.observed),
        label: 'Measured',
      ),
    ];
    const empty = 'Your estimate history appears here as the app recalibrates.';

    if (points.length < 2) {
      return PhysiqueChartCard(
        title: 'Maintenance over time',
        latestValue: points.isEmpty
            ? null
            : '${_ints.format(points.last.kcal)} kcal',
        plot: null,
        legend: legend,
        summary: points.isEmpty
            ? 'No estimates stored yet.'
            : 'One estimate so far. The line starts after the next recalibration.',
        emptyText: empty,
      );
    }

    final t0 = DateTime(
      points.first.estimatedAt.year,
      points.first.estimatedAt.month,
      points.first.estimatedAt.day,
    );
    double xOf(TdeeEstimateResult e) =>
        e.estimatedAt.difference(t0).inHours / 24.0;
    final spots = [for (final e in points) FlSpot(xOf(e), e.kcal.toDouble())];
    final kcals = points.map((e) => e.kcal.toDouble());
    final yr = _range(kcals.reduce(math.min), kcals.reduce(math.max), 200);
    final spanDays = math.max(spots.last.x, 1.0);
    final first = points.first.kcal;
    final last = points.last.kcal;
    final delta = last - first;

    return PhysiqueChartCard(
      title: 'Maintenance over time',
      latestValue: '${_ints.format(last)} kcal',
      legend: legend,
      summary: delta == 0
          ? 'Unchanged since your first estimate.'
          : '${delta > 0 ? 'Up' : 'Down'} ${_ints.format(delta.abs())} kcal '
                'since your first estimate.',
      emptyText: empty,
      plot: LineChart(
        duration: PhysiqueChartStyle.animationDuration(context),
        LineChartData(
          minX: 0,
          maxX: spanDays,
          minY: yr.min,
          maxY: yr.max,
          gridData: PhysiqueChartStyle.grid(context),
          borderData: PhysiqueChartStyle.noBorder,
          titlesData: PhysiqueChartStyle.titles(
            context,
            leftLabel: (v) => _ints.format(v.round()),
            bottomLabel: (v) => DateFormat(
              'd MMM',
            ).format(t0.add(Duration(hours: (v * 24).round()))),
            leftInterval: math.max(((yr.max - yr.min) / 3), 1),
            bottomInterval: math.max(spanDays / 3, 1),
            leftReserved: 48,
          ),
          lineTouchData: PhysiqueChartStyle.touch(
            context,
            format: (s) {
              final e = points[s.spotIndex];
              return '${_ints.format(e.kcal)} kcal\n'
                  '${DateFormat('d MMM').format(e.estimatedAt)}';
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 2,
              color: hx.outline,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 4,
                      color: calibrationMethodColor(hx, points[index].method),
                      strokeWidth: 2,
                      strokeColor: hx.surfaceContainerLowest,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Weight ───────────────────────────────────────────────────────────────────

/// Raw weigh-ins and the smoothed trend the estimate reads its weight change
/// from.
class WeightTrendChart extends StatelessWidget {
  const WeightTrendChart({super.key, required this.series});

  final CalibrationSeries series;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final legend = [
      ChartLegendItem(color: hx.onSurfaceVariant, label: 'Weigh-in'),
      ChartLegendItem(color: hx.primary, label: 'Smoothed trend'),
    ];
    const empty = 'Log your weight a few times a week to see your trend here.';

    if (series.weighIns.length < 2 || series.trend.isEmpty) {
      return PhysiqueChartCard(
        title: 'Weight trend',
        plot: null,
        legend: legend,
        summary: 'The estimate needs at least 4 weigh-ins to read your trend.',
        emptyText: empty,
      );
    }

    final ys = [
      ...series.weighIns.map((p) => p.y),
      ...series.trend.map((p) => p.y),
    ];
    final yr = _range(ys.reduce(math.min), ys.reduce(math.max), 1.0);
    final trendDelta = series.trend.last.y - series.trend.first.y;
    final sign = trendDelta > 0 ? '+' : '';

    return PhysiqueChartCard(
      title: 'Weight trend',
      latestValue: '${PhysiqueChartStyle.kg(series.trend.last.y)} kg',
      legend: legend,
      summary:
          'Trend moved $sign${trendDelta.toStringAsFixed(1)} kg over '
          '${series.days} days. Smoothing keeps water and daily noise out of '
          'the estimate.',
      emptyText: empty,
      plot: LineChart(
        duration: PhysiqueChartStyle.animationDuration(context),
        LineChartData(
          minX: 0,
          maxX: (series.days - 1).toDouble(),
          minY: yr.min,
          maxY: yr.max,
          gridData: PhysiqueChartStyle.grid(context),
          borderData: PhysiqueChartStyle.noBorder,
          titlesData: _dayTitles(
            context,
            series,
            leftLabel: (v) => v.toStringAsFixed(1),
            leftInterval: math.max((yr.max - yr.min) / 3, 0.1),
          ),
          lineTouchData: PhysiqueChartStyle.touch(
            context,
            format: (s) => s.barIndex == 0
                ? '${s.y.toStringAsFixed(1)} kg trend'
                : '${s.y.toStringAsFixed(1)} kg',
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in series.trend) FlSpot(p.x, p.y)],
              isCurved: true,
              curveSmoothness: 0.2,
              barWidth: 3,
              color: hx.primary,
              dotData: PhysiqueChartStyle.lastPointDot(
                context,
                color: hx.primary,
              ),
            ),
            LineChartBarData(
              spots: [for (final p in series.weighIns) FlSpot(p.x, p.y)],
              barWidth: 0,
              color: hx.onSurfaceVariant,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3,
                      color: hx.onSurfaceVariant,
                      strokeWidth: 0,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Intake ───────────────────────────────────────────────────────────────────

/// Calories logged per day, with the average the estimate used.
class IntakeChart extends StatelessWidget {
  const IntakeChart({super.key, required this.series});

  final CalibrationSeries series;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final legend = [
      ChartLegendItem(color: hx.domainNutrition, label: 'Logged day'),
      ChartLegendItem(color: hx.outline, label: 'Average'),
    ];
    const empty = 'Log your food and your daily intake shows up here.';
    final mean = series.meanIntake;

    if (!series.hasIntake || mean == null) {
      return PhysiqueChartCard(
        title: 'Daily intake',
        plot: null,
        legend: legend,
        summary: 'Days without food logged are skipped, not counted as zero.',
        emptyText: empty,
      );
    }

    final top = series.intake.map((p) => p.y).reduce(math.max);
    final maxY = (math.max(top, mean) * 1.15 / 100).ceilToDouble() * 100;

    return PhysiqueChartCard(
      title: 'Daily intake',
      latestValue: '${_ints.format(mean.round())} kcal avg',
      legend: legend,
      summary:
          '${series.intake.length} of ${series.days} days logged. Days '
          'without food are skipped, not counted as zero.',
      emptyText: empty,
      plot: BarChart(
        duration: PhysiqueChartStyle.animationDuration(context),
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceBetween,
          gridData: PhysiqueChartStyle.grid(context),
          borderData: PhysiqueChartStyle.noBorder,
          titlesData: _dayTitles(
            context,
            series,
            leftLabel: (v) => _ints.format(v.round()),
            leftInterval: maxY / 3,
            leftReserved: 48,
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: mean,
                color: hx.outline,
                strokeWidth: 1.5,
                dashArray: const [6, 4],
              ),
            ],
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => hx.surfaceContainer,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${_ints.format(rod.toY.round())} kcal\n'
                '${DateFormat('d MMM').format(series.dateAt(group.x.toDouble()))}',
                TextStyle(color: hx.onSurface, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (final p in series.intake)
              BarChartGroupData(
                x: p.x.round(),
                barRods: [
                  BarChartRodData(
                    toY: p.y,
                    width: math.max(3, 220 / series.days),
                    color: hx.domainNutrition,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

FlTitlesData _dayTitles(
  BuildContext context,
  CalibrationSeries series, {
  required String Function(double) leftLabel,
  required double leftInterval,
  double leftReserved = 44,
}) {
  return PhysiqueChartStyle.titles(
    context,
    leftLabel: leftLabel,
    bottomLabel: (v) => DateFormat('d MMM').format(series.dateAt(v)),
    leftInterval: leftInterval,
    bottomInterval: math.max((series.days / 3).floorToDouble(), 1),
    leftReserved: leftReserved,
  );
}
