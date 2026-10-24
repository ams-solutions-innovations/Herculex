import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/steps/domain/step_lifting_correlation.dart';

/// Scatter chart showing empirical correlation between daily step volume and workout RPE.
class StepLiftingCorrelationChart extends StatelessWidget {
  final StepLiftingCorrelation correlation;

  const StepLiftingCorrelationChart({super.key, required this.correlation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = correlation.stepsVsRpePoints;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STEPS VS. WORKOUT RPE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Daily steps in thousands (X) vs. Session RPE (Y)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.tertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'R² FIT: ${correlation.r2Rpe.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: points.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No correlation data available yet.\nLog workouts and step counts to observe how NEAT affects gym effort.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : _buildScatter(points),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correlation.rpeInsight,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScatter(List<CorrelationPoint> points) {
    final minXVal = points.map((p) => p.x).reduce(math.min);
    final maxXVal = points.map((p) => p.x).reduce(math.max);
    final minYVal = points.map((p) => p.y).reduce(math.min);
    final maxYVal = points.map((p) => p.y).reduce(math.max);

    final minX = math.max(0.0, (minXVal - 1.0).floorToDouble());
    final maxX = (maxXVal + 1.0).ceilToDouble();
    final safeMaxX = (maxX - minX < 4.0) ? minX + 4.0 : maxX;

    final minY = math.max(1.0, (minYVal - 0.5).floorToDouble());
    final maxY = math.min(10.0, (maxYVal + 0.5).ceilToDouble());
    final safeMaxY = (maxY - minY < 2.0) ? math.min(10.0, minY + 2.0) : maxY;

    return ScatterChart(
      ScatterChartData(
        minX: minX,
        maxX: safeMaxX,
        minY: minY,
        maxY: safeMaxY,
        scatterSpots: points
            .map(
              (p) => ScatterSpot(
                p.x,
                p.y,
                dotPainter: FlDotCirclePainter(
                  radius: 5.5,
                  color: const Color(0xFFF59E0B),
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
            )
            .toList(),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 2.0,
          verticalInterval: 5.0,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 2.0,
              getTitlesWidget: (val, _) => Text(
                'RPE ${val.toInt()}',
                style: TextStyle(color: AppColors.secondary, fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 5.0,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}k',
                style: TextStyle(color: AppColors.secondary, fontSize: 9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
