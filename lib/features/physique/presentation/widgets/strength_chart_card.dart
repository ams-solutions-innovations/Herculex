import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_card_frame.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_style.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:intl/intl.dart';

/// Estimated 1RM for one canonical lift at a time, with a lift selector.
class StrengthChartCard extends ConsumerWidget {
  const StrengthChartCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(physiqueStrengthChartProvider(goalId));
    final range = ref.watch(physiqueEffectiveRangeProvider(goalId));
    final hx = context.hx;
    final points = data.points;
    final lift = data.lift;

    return PhysiqueChartCard(
      title: 'Strength',
      latestValue: points.isEmpty
          ? null
          : '${PhysiqueChartStyle.kg(points.last.value)} kg',
      header: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final l in PrimaryLift.values)
              Padding(
                padding: const EdgeInsets.only(right: HxSpace.x2),
                child: _LiftPill(
                  lift: l,
                  selected: l == lift,
                  enabled: data.liftsWithData.contains(l),
                  onTap: () =>
                      ref.read(physiqueSelectedLiftProvider.notifier).state = l,
                ),
              ),
          ],
        ),
      ),
      plot: points.length < 2
          ? null
          : _StrengthPlot(points: points, color: hx.domainTraining),
      legend: [
        ChartLegendItem(color: hx.domainTraining, label: 'Estimated 1RM'),
      ],
      summary: _summary(points, range),
      emptyText:
          'Log a ${(lift ?? PrimaryLift.squat).label} set to see your '
          'strength trend.',
    );
  }
}

String _summary(List<ChartPoint> points, ChartRange range) {
  if (points.length < 2) return 'Not enough sets logged yet.';
  final delta = points.last.value - points.first.value;
  final span =
      TrendSeries.dayNumber(points.last.date) -
      TrendSeries.dayNumber(points.first.date);
  final period = PhysiqueChartStyle.periodLabel(range, span);
  final rounded = (delta.abs() * 10).round() / 10;
  if (rounded == 0) return 'No change over $period.';
  final dir = delta < 0 ? 'Down' : 'Up';
  return '$dir ${PhysiqueChartStyle.kg(rounded)} kg over $period.';
}

class _LiftPill extends StatelessWidget {
  const _LiftPill({
    required this.lift,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PrimaryLift lift;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Align(
        child: HxPill(
          selected: selected,
          onTap: enabled ? onTap : null,
          child: Text(
            lift.label,
            style: enabled ? null : TextStyle(color: context.hx.tertiary),
          ),
        ),
      ),
    );
  }
}

class _StrengthPlot extends StatelessWidget {
  const _StrengthPlot({required this.points, required this.color});

  final List<ChartPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final origin = points.first.date;
    final originDay = TrendSeries.dayNumber(origin);
    final spots = [
      for (final p in points)
        FlSpot((TrendSeries.dayNumber(p.date) - originDay).toDouble(), p.value),
    ];
    final maxX = spots.last.x;
    var minY = spots.map((s) => s.y).reduce(math.min);
    var maxY = spots.map((s) => s.y).reduce(math.max);
    minY = (minY - 5).floorToDouble();
    maxY = (maxY + 5).ceilToDouble();
    final leftInterval = math.max(1.0, ((maxY - minY) / 3).ceilToDouble());
    final bottomInterval = math.max(1.0, (maxX / 3).ceilToDouble());
    final fmt = DateFormat('MMM d');
    DateTime dateAt(double x) =>
        DateTime(origin.year, origin.month, origin.day + x.round());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
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
          bottomLabel: (v) => fmt.format(dateAt(v)),
        ),
        lineTouchData: PhysiqueChartStyle.touch(
          context,
          format: (s) =>
              '${fmt.format(dateAt(s.x))}: ${PhysiqueChartStyle.kg(s.y)} kg',
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            dotData: PhysiqueChartStyle.lastPointDot(context, color: color),
          ),
        ],
      ),
      duration: PhysiqueChartStyle.animationDuration(context),
    );
  }
}
