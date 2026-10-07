import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/domain/physique_strength_series.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_card_frame.dart';
import 'package:herculex/features/physique/presentation/widgets/chart_style.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:intl/intl.dart';

/// Training level as level names, from workout history only (D-12).
class TrainingLevelChartCard extends ConsumerWidget {
  const TrainingLevelChartCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(physiqueTrainingLevelChartProvider(goalId));
    final hx = context.hx;

    return PhysiqueChartCard(
      title: 'Training level',
      latestValue: points.isEmpty ? null : points.last.level.label,
      plot: points.length < 2
          ? null
          : _LevelPlot(points: points, color: hx.domainTraining),
      legend: [ChartLegendItem(color: hx.domainTraining, label: 'Level')],
      caption: 'Based on your training history, not your XP rank.',
      summary: _summary(points),
      emptyText: 'Keep training and your level will appear here.',
    );
  }
}

String _summary(List<TrainingLevelPoint> points) {
  if (points.length < 2) return 'Not enough training history yet.';
  final current = points.last;
  for (var i = points.length - 1; i > 0; i--) {
    if (points[i].level != points[i - 1].level) {
      final month = DateFormat('MMMM').format(points[i].date);
      return 'Reached ${points[i].level.label} in $month.';
    }
  }
  return 'Currently ${current.level.label}.';
}

class _LevelPlot extends StatelessWidget {
  const _LevelPlot({required this.points, required this.color});

  final List<TrainingLevelPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final origin = points.first.date;
    final originDay = TrendSeries.dayNumber(origin);
    final spots = [
      for (final p in points)
        FlSpot(
          (TrendSeries.dayNumber(p.date) - originDay).toDouble(),
          p.level.index.toDouble(),
        ),
    ];
    final maxX = math.max(1.0, spots.last.x);
    final bottomInterval = math.max(1.0, (maxX / 3).ceilToDouble());
    final fmt = DateFormat('MMM d');
    final levels = ExperienceLevel.values;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: -0.25,
        maxY: levels.length - 1 + 0.25,
        gridData: PhysiqueChartStyle.grid(context, horizontalInterval: 1),
        borderData: PhysiqueChartStyle.noBorder,
        titlesData: PhysiqueChartStyle.titles(
          context,
          leftInterval: 1,
          bottomInterval: bottomInterval,
          leftReserved: 96,
          leftLabel: (v) {
            final i = v.round();
            if ((v - i).abs() > 0.01 || i < 0 || i >= levels.length) return '';
            return levels[i].label;
          },
          bottomLabel: (v) => fmt.format(
            DateTime(origin.year, origin.month, origin.day + v.round()),
          ),
        ),
        lineTouchData: PhysiqueChartStyle.touch(
          context,
          format: (s) {
            final i = s.y.round().clamp(0, levels.length - 1);
            final date = DateTime(
              origin.year,
              origin.month,
              origin.day + s.x.round(),
            );
            return '${fmt.format(date)}: ${levels[i].label}';
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isStepLineChart: true,
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
