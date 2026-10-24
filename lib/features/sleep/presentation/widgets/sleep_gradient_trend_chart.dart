// lib/features/sleep/presentation/widgets/sleep_gradient_trend_chart.dart
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';
import 'package:intl/intl.dart';

/// Animated gradient spline chart displaying sleep history trends with target lines.
class SleepGradientTrendChart extends StatefulWidget {
  final List<SleepRecord> history;
  final double targetHours;

  const SleepGradientTrendChart({
    super.key,
    required this.history,
    this.targetHours = 8.0,
  });

  @override
  State<SleepGradientTrendChart> createState() =>
      _SleepGradientTrendChartState();
}

class _SleepGradientTrendChartState extends State<SleepGradientTrendChart> {
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedRecords = widget.history
        .take(_selectedDays)
        .toList()
        .reversed
        .toList();

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with 7D / 30D switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SLEEP DURATION TREND',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Trailing $_selectedDays days (target: ${widget.targetHours.toStringAsFixed(0)}h)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.tertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildTimeframePill('7D', 7),
                  const SizedBox(width: 6),
                  _buildTimeframePill('30D', 30),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chart
          SizedBox(
            height: 190,
            child: displayedRecords.isEmpty
                ? Center(
                    child: Text(
                      'No sleep history records available yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : _buildLineChart(displayedRecords, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframePill(String label, int days) {
    final isSelected = _selectedDays == days;
    return InkWell(
      onTap: () => setState(() => _selectedDays = days),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : AppColors.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(List<SleepRecord> records, ThemeData theme) {
    final spots = <FlSpot>[];
    for (var i = 0; i < records.length; i++) {
      spots.add(FlSpot(i.toDouble(), records[i].totalHours));
    }

    final maxVal = records
        .map((r) => r.totalHours)
        .fold(widget.targetHours, math.max);
    final maxY = math.max(10.0, (maxVal + 1.0).ceilToDouble());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1.0, (records.length - 1).toDouble()),
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E1B4B),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.spotIndex;
                final r = (idx >= 0 && idx < records.length)
                    ? records[idx]
                    : null;
                final dateStr = r?.dateIso ?? '';
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}h\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: dateStr,
                      style: const TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 2.0,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (val) {
            if ((val - widget.targetHours).abs() < 0.1) {
              return FlLine(
                color: const Color(0xFF10B981).withValues(alpha: 0.5),
                strokeWidth: 1.5,
                dashArray: [6, 4],
              );
            }
            return FlLine(
              color: Colors.white.withValues(alpha: 0.05),
              strokeWidth: 1,
            );
          },
        ),
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
              getTitlesWidget: (val, _) {
                if (val == 0) return const SizedBox.shrink();
                return Text(
                  '${val.toInt()}h',
                  style: TextStyle(color: AppColors.secondary, fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: _selectedDays == 7 ? 1.0 : 5.0,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= records.length)
                  return const SizedBox.shrink();
                final dateStr = records[idx].dateIso;
                try {
                  final dt = DateTime.parse(dateStr);
                  final label = DateFormat(
                    _selectedDays == 7 ? 'E' : 'd/M',
                  ).format(dt);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: TextStyle(color: AppColors.secondary, fontSize: 9),
                    ),
                  );
                } catch (_) {
                  return const SizedBox.shrink();
                }
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            preventCurveOverShooting: true,
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
            ),
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: _selectedDays == 7,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: const Color(0xFF06B6D4),
                strokeWidth: 2,
                strokeColor: const Color(0xFF0F172A),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF6366F1).withValues(alpha: 0.4),
                  const Color(0xFF06B6D4).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
