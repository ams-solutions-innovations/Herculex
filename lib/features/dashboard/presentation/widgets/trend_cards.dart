import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers.dart';
import '../../../../core/units.dart';
import '../../../../theme/haptics.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../nutrition/domain/daily_totals.dart';
import '../../../nutrition/presentation/goals_providers.dart';
import '../../../nutrition/presentation/nutrition_providers.dart';
import '../../../nutrition/presentation/widgets/macro_chart.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';

/// Standalone preview card for 7-day calorie trends.
class CalorieTrendPreviewCard extends ConsumerWidget {
  const CalorieTrendPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final historyAsync = ref.watch(nutritionHistoryProvider);
    final avg = ref.watch(averageWeeklyCaloriesProvider);
    final targets =
        ref.watch(effectiveTargetsProvider(DateTime.now())).asData?.value ??
        ref.watch(baselineTargetsProvider);

    final spots = historyAsync.asData?.value == null
        ? null
        : _lastKcalDays(historyAsync.asData!.value, 7);

    return _TrendPreviewCard(
      label: 'AVG. DAILY INTAKE · 7D',
      value: avg == null ? '—' : '${avg.round()} kcal/day',
      accent: hx.domainNutrition,
      spots: spots,
      targetValue: targets?.kcal.toDouble(),
      onTap: () => context.push('/nutrition/weekly-stats'),
    );
  }
}

/// Standalone preview card for bodyweight trends.
class BodyweightTrendPreviewCard extends ConsumerWidget {
  const BodyweightTrendPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final history = ref.watch(bodyweightHistoryProvider).asData?.value;
    final fmt = ref.watch(weightFormatProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final goalWeight = ref.watch(goalWeightProvider);
    final targetKg = profile?.targetWeightKg ?? goalWeight;

    final spots = history == null
        ? null
        : [
            for (final (i, r) in history.indexed) FlSpot(i.toDouble(), r.value),
          ];
    final latest = history == null || history.isEmpty ? null : history.last.value;

    return _TrendPreviewCard(
      label: 'BODYWEIGHT',
      value: latest == null ? '—' : fmt.format(latest),
      accent: hx.domainRecovery,
      spots: spots,
      targetValue: targetKg,
      onTap: () => context.push('/measurements/bodyweight'),
    );
  }
}

/// Swipeable row of compact trend previews, replacing the interactive charts
/// that used to sit inline on the dashboard (macro trend + bodyweight
/// sparkline). Each preview is read-only — tapping it opens the real,
/// interactive chart on its own page.
class TrendCardsRow extends ConsumerStatefulWidget {
  const TrendCardsRow({super.key});

  @override
  ConsumerState<TrendCardsRow> createState() => _TrendCardsRowState();
}

class _TrendCardsRowState extends ConsumerState<TrendCardsRow> {
  final _controller = PageController(viewportFraction: 1);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      CalorieTrendPreviewCard(),
      BodyweightTrendPreviewCard(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 146,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) {
              Haptics.selection();
              setState(() => _page = i);
            },
            children: pages,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              AnimatedContainer(
                duration: HxMotion.base,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? context.hx.primary
                      : context.hx.outlineVariant,
                  borderRadius: HxRadius.pillAll,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

List<FlSpot> _lastKcalDays(Map<String, DailyTotals> historyMap, int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final spots = <FlSpot>[];
  for (var i = days - 1; i >= 0; i--) {
    final date = today.subtract(Duration(days: i));
    final iso = DateFormat('yyyy-MM-dd').format(date);
    final totals = historyMap[iso] ?? DailyTotals.empty;
    spots.add(FlSpot((days - 1 - i).toDouble(), macroValueForTotals(totals, 'kcal')));
  }
  return spots;
}

/// Compact, non-interactive chart card: label, headline value, tiny
/// sparkline, chevron, styled with a modern Dream Physique AI gradient
/// background and squircle border radius.
class _TrendPreviewCard extends ConsumerWidget {
  const _TrendPreviewCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.spots,
    required this.onTap,
    this.targetValue,
  });

  final String label;
  final String value;
  final Color accent;
  final List<FlSpot>? spots;
  final VoidCallback onTap;
  final double? targetValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final hasData = spots != null && spots!.any((s) => s.y > 0);
    final hasTarget = targetValue != null &&
        targetValue! > 0 &&
        !targetValue!.isNaN &&
        !targetValue!.isInfinite;

    double? chartMinY;
    double? chartMaxY;
    if (spots != null && spots!.isNotEmpty) {
      var minY = spots!.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      var maxY = spots!.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      if (hasTarget) {
        if (targetValue! < minY) minY = targetValue!;
        if (targetValue! > maxY) maxY = targetValue!;
      }
      final padding = (maxY - minY) * 0.15;
      final effectivePadding = padding == 0 ? 1.0 : padding;
      chartMinY = minY - effectivePadding;
      chartMaxY = maxY + effectivePadding;
    }

    return dashboardCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.secondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: hx.secondary),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: !hasData
                ? Center(
                    child: Text(
                      'Not enough data yet',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hx.secondary),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: chartMinY,
                      maxY: chartMaxY,
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      extraLinesData: hasTarget
                          ? ExtraLinesData(
                              horizontalLines: [
                                HorizontalLine(
                                  y: targetValue!,
                                  color: accent.withValues(alpha: 0.5),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4],
                                ),
                              ],
                            )
                          : null,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots!,
                          isCurved: true,
                          color: accent,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: accent.withValues(alpha: 0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
