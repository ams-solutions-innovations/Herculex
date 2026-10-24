import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/steps/domain/step_record.dart';

/// Animated gradient bar chart displaying hourly step distribution across the day.
class StepHourlyBarChart extends StatelessWidget {
  final StepRecord? record;

  const StepHourlyBarChart({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hourly = record?.hourlySteps ?? const {};

    // Group 24 hours into 8 three-hour intervals for balanced mobile layout
    // 00-02, 03-05, 06-08, 09-11, 12-14, 15-17, 18-20, 21-23
    final intervals = <int>[];
    int peakIndex = 0;
    int maxStepsInInterval = 0;

    for (int i = 0; i < 8; i++) {
      final startHour = i * 3;
      final sum =
          (hourly[startHour] ?? 0) +
          (hourly[startHour + 1] ?? 0) +
          (hourly[startHour + 2] ?? 0);
      intervals.add(sum);
      if (sum > maxStepsInInterval) {
        maxStepsInInterval = sum;
        peakIndex = i;
      }
    }

    final peakHourLabel = '${peakIndex * 3}:00-${(peakIndex * 3) + 2}:59';

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOURLY DISTRIBUTION',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Activity pacing throughout the day',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.tertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (maxStepsInInterval > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Peak $peakHourLabel',
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: intervals.every((count) => count == 0)
                ? Center(
                    child: Text(
                      'No hourly activity recorded today.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : _buildBarChart(intervals, theme, maxStepsInInterval),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<int> intervals, ThemeData theme, int maxSteps) {
    const labels = ['00h', '03h', '06h', '09h', '12h', '15h', '18h', '21h'];
    final maxY = (maxSteps * 1.25).clamp(500, 100000).toDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E293B),
            tooltipRoundedRadius: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${labels[groupIndex]}\n${rod.toY.round()} steps',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[idx],
                    style: TextStyle(
                      color: AppColors.tertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(intervals.length, (i) {
          final count = intervals[i].toDouble();
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count,
                width: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xFFF59E0B), // Amber
                    Color(0xFF06B6D4), // Cyan
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
