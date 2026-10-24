part of '../insights_view.dart';

class _SleepVsRpeCard extends ConsumerWidget {
  const _SleepVsRpeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final async = ref.watch(sleepVsRpeProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sleep vs. Gym RPE',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: hx.secondary),
                onPressed: () => _showMethodologyDialog(
                  context,
                  "Sleep vs. RPE Correlation",
                  "R² (Coefficient of Determination) indicates the percentage of variation in perceived session RPE that can be explained by sleep duration. A higher R² indicates that sleep heavily impacts recovery stress levels.",
                ),
              ),
            ],
          ),
          Text(
            'Sleep duration hours (X) vs. average session RPE (Y)',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: 24),
          async.when(
            data: (res) {
              if (res.points.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No correlation data available yet.\nLog workouts and sleep to see analysis.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hx.secondary,
                      ),
                    ),
                  ),
                );
              }

              final minXVal = res.points.map((p) => p.x).reduce(min);
              final maxXVal = res.points.map((p) => p.x).reduce(max);
              final minYVal = res.points.map((p) => p.y).reduce(min);
              final maxYVal = res.points.map((p) => p.y).reduce(max);

              // Smart bounds with breathing room
              final minX = max(0.0, (minXVal - 0.6).floorToDouble());
              final maxX = (maxXVal + 0.6).ceilToDouble();
              final safeMaxX = (maxX - minX < 2.0) ? minX + 2.0 : maxX;
              final xSpan = safeMaxX - minX;
              final xInterval = xSpan <= 4.0
                  ? 1.0
                  : (xSpan <= 8.0 ? 2.0 : (xSpan / 4).ceilToDouble());

              final minY = max(1.0, (minYVal - 0.5).floorToDouble());
              final maxY = min(10.0, (maxYVal + 0.5).ceilToDouble());
              final safeMaxY = (maxY - minY < 2.0)
                  ? min(10.0, minY + 2.0)
                  : maxY;
              final safeMinY = (safeMaxY - minY < 2.0)
                  ? max(1.0, safeMaxY - 2.0)
                  : minY;
              final ySpan = safeMaxY - safeMinY;
              final yInterval = ySpan <= 3.0 ? 1.0 : (ySpan / 4).ceilToDouble();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      height: 180,
                      child: ScatterChart(
                        ScatterChartData(
                          minX: minX,
                          maxX: safeMaxX,
                          minY: safeMinY,
                          maxY: safeMaxY,
                          scatterSpots: res.points
                              .map(
                                (p) => ScatterSpot(
                                  p.x,
                                  p.y,
                                  dotPainter: FlDotCirclePainter(
                                    radius: 6,
                                    color: hx.primary,
                                  ),
                                ),
                              )
                              .toList(),
                          gridData: FlGridData(
                            show: true,
                            horizontalInterval: yInterval,
                            verticalInterval: xInterval,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: hx.outlineVariant.withValues(alpha: 0.2),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                            getDrawingVerticalLine: (_) => FlLine(
                              color: hx.outlineVariant.withValues(alpha: 0.2),
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
                                reservedSize: 32,
                                interval: yInterval,
                                getTitlesWidget: (val, _) {
                                  return Text(
                                    val.toStringAsFixed(val % 1 == 0 ? 0 : 1),
                                    style: TextStyle(
                                      color: hx.secondary,
                                      fontSize: 10,
                                    ),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                interval: xInterval,
                                getTitlesWidget: (val, _) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${val.toStringAsFixed(val % 1 == 0 ? 0 : 1)}h',
                                      style: TextStyle(
                                        color: hx.secondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "R² FIT INDEX: ${res.r2.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          res.interpretation,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: hx.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

class _HrVsTonnageCard extends ConsumerWidget {
  const _HrVsTonnageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final async = ref.watch(hrVsTonnageProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Resting HR vs. Tonnage',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: hx.secondary),
                onPressed: () => _showMethodologyDialog(
                  context,
                  "Resting HR vs. Tonnage Correlation",
                  "Elevated resting heart rate indicates systemic stress. This scatter plot tracks whether higher heart rates correlate with decreased absolute session volume (tonnage).",
                ),
              ),
            ],
          ),
          Text(
            'Resting HR bpm (X) vs. session tonnage kg (Y)',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: 24),
          async.when(
            data: (res) {
              if (res.points.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No correlation data available yet.\nLog workouts and heart rate samples to see analysis.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hx.secondary,
                      ),
                    ),
                  ),
                );
              }

              final minXVal = res.points.map((p) => p.x).reduce(min);
              final maxXVal = res.points.map((p) => p.x).reduce(max);
              final minYVal = res.points.map((p) => p.y).reduce(min);
              final maxYVal = res.points.map((p) => p.y).reduce(max);

              // Smart bounds for HR (X: bpm)
              final minX = max(30.0, ((minXVal - 5) / 5).floor() * 5.0);
              final maxX = ((maxXVal + 5) / 5).ceil() * 5.0;
              final safeMaxX = (maxX - minX < 15.0) ? minX + 15.0 : maxX;
              final xSpan = safeMaxX - minX;
              final xInterval = xSpan <= 20.0
                  ? 5.0
                  : (xSpan <= 40.0 ? 10.0 : (xSpan / 4).ceilToDouble());

              // Smart bounds for Tonnage (Y: kg)
              final minY = max(0.0, ((minYVal * 0.9) / 500).floor() * 500.0);
              final maxY = ((maxYVal * 1.1) / 500).ceil() * 500.0;
              final safeMaxY = (maxY - minY < 1000.0) ? minY + 1000.0 : maxY;
              final ySpan = safeMaxY - minY;
              final yInterval = ySpan <= 2000.0
                  ? 500.0
                  : (ySpan <= 5000.0
                        ? 1000.0
                        : (ySpan / 4 / 500).ceil() * 500.0);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      height: 180,
                      child: ScatterChart(
                        ScatterChartData(
                          minX: minX,
                          maxX: safeMaxX,
                          minY: minY,
                          maxY: safeMaxY,
                          scatterSpots: res.points
                              .map(
                                (p) => ScatterSpot(
                                  p.x,
                                  p.y,
                                  dotPainter: FlDotCirclePainter(
                                    radius: 6,
                                    color: Colors.teal,
                                  ),
                                ),
                              )
                              .toList(),
                          gridData: FlGridData(
                            show: true,
                            horizontalInterval: yInterval,
                            verticalInterval: xInterval,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: hx.outlineVariant.withValues(alpha: 0.2),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                            getDrawingVerticalLine: (_) => FlLine(
                              color: hx.outlineVariant.withValues(alpha: 0.2),
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
                                reservedSize: 38,
                                interval: yInterval,
                                getTitlesWidget: (val, _) {
                                  final label = val >= 1000
                                      ? '${(val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k'
                                      : '${val.toInt()}';
                                  return Text(
                                    label,
                                    style: TextStyle(
                                      color: hx.secondary,
                                      fontSize: 10,
                                    ),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                interval: xInterval,
                                getTitlesWidget: (val, _) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${val.toInt()}',
                                      style: TextStyle(
                                        color: hx.secondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "R² FIT INDEX: ${res.r2.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          res.interpretation,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

void _showMethodologyDialog(
  BuildContext context,
  String title,
  String description,
) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CLOSE",
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
