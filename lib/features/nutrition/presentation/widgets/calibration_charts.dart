import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_calibration_series.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
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

/// Clean axis bounds where [min] and [max] are exact multiples of [interval],
/// preventing `fl_chart` from drawing colliding min/max edge labels next to
/// interior interval ticks.
({double min, double max, double interval}) _niceAxis(
  double lo,
  double hi, {
  required List<double> steps,
  required double minPad,
}) {
  final span = math.max(hi - lo, 0.0);
  // Small clearance so points on or near a grid line have breathing room
  // without jumping an entire extra step when floor/ceil already adds padding.
  final pad = math.max(span * 0.04, minPad);
  final targetLo = lo - pad;
  final targetHi = hi + pad;

  for (final step in steps) {
    var minVal = (targetLo / step).floorToDouble() * step;
    var maxVal = (targetHi / step).ceilToDouble() * step;
    if (maxVal - minVal < 2 * step) {
      final mid = ((lo + hi) / 2 / step).roundToDouble() * step;
      minVal = mid - step;
      maxVal = mid + step;
    }
    final count = ((maxVal - minVal) / step).round();
    if (count <= 4) {
      return (min: minVal, max: maxVal, interval: step);
    }
  }

  final fallback = steps.last;
  final minVal = (targetLo / fallback).floorToDouble() * fallback;
  final maxVal = math.max(
    minVal + 2 * fallback,
    (targetHi / fallback).ceilToDouble() * fallback,
  );
  return (min: minVal, max: maxVal, interval: fallback);
}

/// Clean zero-based axis where [max] is an exact 3x or 4x multiple of
/// [interval], so calorie labels are always round numbers (e.g. 0, 1,000,
/// 2,000, 3,000, 4,000) and never fractional thirds like 1,233 / 2,467.
({double max, double interval}) _niceZeroAxis(double peak) {
  const steps = <double>[200, 250, 500, 750, 1000, 1250, 1500, 2000, 2500];
  final target = math.max(peak * 1.12, 600.0);
  for (final step in steps) {
    for (final divisions in const [3, 4]) {
      final maxVal = divisions * step;
      if (maxVal >= target) {
        return (max: maxVal, interval: step);
      }
    }
  }
  final step = (target / 4 / 500).ceilToDouble() * 500;
  return (max: step * 4, interval: step);
}

/// Up to 4 evenly-spaced integer day indices across `0..maxIndex` so X-axis
/// date labels never overlap on either `LineChart` or `BarChart`.
Set<int> _xTickIndices(int maxIndex) {
  if (maxIndex <= 0) return const {0};
  if (maxIndex <= 3) return {for (var i = 0; i <= maxIndex; i++) i};
  return {
    0,
    (maxIndex / 3).round(),
    (maxIndex * 2 / 3).round(),
    maxIndex,
  };
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
    final yr = _niceAxis(
      kcals.reduce(math.min),
      kcals.reduce(math.max),
      steps: const [50, 100, 200, 250, 500, 1000],
      minPad: 50,
    );
    final spanDays = math.max(spots.last.x.ceilToDouble(), 1.0);
    final first = points.first.kcal;
    final last = points.last.kcal;
    final delta = last - first;
    final bottomInterval = math.max((spanDays / 3).roundToDouble(), 1.0);

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
          clipData: const FlClipData.all(),
          gridData: PhysiqueChartStyle.grid(
            context,
            horizontalInterval: yr.interval,
          ),
          borderData: PhysiqueChartStyle.noBorder,
          titlesData: _buildTitles(
            context,
            leftLabel: (v) => _ints.format(v.round()),
            leftInterval: yr.interval,
            leftReserved: 48,
            bottomInterval: bottomInterval,
            bottomLabel: (v, meta) {
              if ((v - meta.max).abs() > 1e-4 &&
                  (meta.max - v) < bottomInterval * 0.5) {
                return null;
              }
              return DateFormat(
                'd MMM',
              ).format(t0.add(Duration(hours: (v * 24).round())));
            },
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
    final yr = _niceAxis(
      ys.reduce(math.min),
      ys.reduce(math.max),
      steps: const [0.2, 0.5, 1.0, 1.5, 2.0, 2.5, 5.0, 10.0],
      minPad: 0.2,
    );
    final trendDelta = series.trend.last.y - series.trend.first.y;
    final sign = trendDelta > 0 ? '+' : '';
    final maxIndex = math.max(series.days - 1, 1);
    final ticks = _xTickIndices(maxIndex);

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
          maxX: maxIndex.toDouble(),
          minY: yr.min,
          maxY: yr.max,
          clipData: const FlClipData.all(),
          gridData: PhysiqueChartStyle.grid(
            context,
            horizontalInterval: yr.interval,
          ),
          borderData: PhysiqueChartStyle.noBorder,
          titlesData: _buildTitles(
            context,
            leftLabel: (v) => v.toStringAsFixed(1),
            leftInterval: yr.interval,
            leftReserved: 44,
            bottomInterval: 1,
            bottomLabel: (v, _) {
              final idx = v.round();
              if ((v - idx).abs() > 1e-3 || !ticks.contains(idx)) return null;
              return DateFormat('d MMM').format(series.dateAt(idx.toDouble()));
            },
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
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    hx.primary.withValues(alpha: 0.14),
                    hx.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
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
                      radius: 3.5,
                      color: hx.onSurfaceVariant,
                      strokeWidth: 1.5,
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
      ChartLegendItem(color: hx.onSurfaceVariant, label: 'Average'),
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
    final axis = _niceZeroAxis(math.max(top, mean));
    final byDay = <int, double>{
      for (final p in series.intake) p.x.round(): p.y,
    };
    final maxIndex = math.max(series.days - 1, 0);
    final ticks = _xTickIndices(maxIndex);

    return PhysiqueChartCard(
      title: 'Daily intake',
      latestValue: '${_ints.format(mean.round())} kcal avg',
      legend: legend,
      summary:
          '${series.intake.length} of ${series.days} days logged. Days '
          'without food are skipped, not counted as zero.',
      emptyText: empty,
      plot: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = math.max(constraints.maxWidth - 48, 120.0);
          final rodWidth = (plotWidth / math.max(series.days, 1) * 0.62).clamp(
            4.0,
            14.0,
          );
          return BarChart(
            duration: PhysiqueChartStyle.animationDuration(context),
            BarChartData(
              minY: 0,
              maxY: axis.max,
              alignment: BarChartAlignment.spaceBetween,
              gridData: PhysiqueChartStyle.grid(
                context,
                horizontalInterval: axis.interval,
              ),
              borderData: PhysiqueChartStyle.noBorder,
              titlesData: _buildTitles(
                context,
                leftLabel: (v) => _ints.format(v.round()),
                leftInterval: axis.interval,
                leftReserved: 48,
                bottomInterval: 1,
                bottomLabel: (v, _) {
                  final idx = v.round();
                  if (!ticks.contains(idx)) return null;
                  return DateFormat(
                    'd MMM',
                  ).format(series.dateAt(idx.toDouble()));
                },
              ),
              extraLinesData: ExtraLinesData(
                extraLinesOnTop: true,
                horizontalLines: [
                  HorizontalLine(
                    y: mean,
                    color: hx.onSurfaceVariant.withValues(alpha: 0.75),
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                  ),
                ],
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => hx.surfaceContainer,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (!byDay.containsKey(group.x)) return null;
                    return BarTooltipItem(
                      '${_ints.format(rod.toY.round())} kcal\n'
                      '${DateFormat('d MMM').format(series.dateAt(group.x.toDouble()))}',
                      TextStyle(
                        color: hx.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < series.days; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: byDay[i] ?? 0,
                        width: rodWidth,
                        color: byDay.containsKey(i)
                            ? hx.domainNutrition
                            : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

FlTitlesData _buildTitles(
  BuildContext context, {
  required String Function(double) leftLabel,
  required double leftInterval,
  required double leftReserved,
  required double bottomInterval,
  required String? Function(double, TitleMeta) bottomLabel,
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
        getTitlesWidget: (value, meta) {
          if ((value - meta.min).abs() > 1e-4 &&
              (value - meta.min) < leftInterval * 0.5) {
            return const SizedBox.shrink();
          }
          if ((meta.max - value).abs() > 1e-4 &&
              (meta.max - value) < leftInterval * 0.5) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(leftLabel(value), style: style),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 30,
        interval: bottomInterval,
        getTitlesWidget: (value, meta) {
          final text = bottomLabel(value, meta);
          if (text == null) return const SizedBox.shrink();
          return SideTitleWidget(
            axisSide: meta.axisSide,
            fitInside: SideTitleFitInsideData.fromTitleMeta(
              meta,
              distanceFromEdge: 0,
            ),
            child: Text(text, style: style),
          );
        },
      ),
    ),
  );
}
