import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/units.dart';
import '../../../../theme/haptics.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../../../nutrition/domain/daily_totals.dart';
import '../../../nutrition/presentation/nutrition_providers.dart';
import '../../../nutrition/presentation/widgets/macro_chart.dart';
import '../dashboard_providers.dart';

/// Swipeable row of compact trend previews, replacing the interactive charts
/// that used to sit inline on the dashboard (macro trend + bodyweight
/// sparkline). Each preview is read-only — tapping it opens the real,
/// interactive chart on its own page (UI-rework P4).
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
    final pages = const [_NutritionTrendPreview(), _BodyweightTrendPreview()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 148,
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

class _NutritionTrendPreview extends ConsumerWidget {
  const _NutritionTrendPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final historyAsync = ref.watch(nutritionHistoryProvider);
    final avg = ref.watch(averageWeeklyCaloriesProvider);

    final spots = historyAsync.asData?.value == null
        ? null
        : _lastKcalDays(historyAsync.asData!.value, 7);

    return _TrendPreviewCard(
      label: 'CALORIES · 7D',
      value: avg == null ? '—' : '${avg.round()} kcal/day',
      accent: hx.domainNutrition,
      spots: spots,
      onTap: () => context.push('/nutrition/weekly-stats'),
    );
  }
}

class _BodyweightTrendPreview extends ConsumerWidget {
  const _BodyweightTrendPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final history = ref.watch(bodyweightHistoryProvider).asData?.value;
    final fmt = ref.watch(weightFormatProvider);

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
      onTap: () => context.push('/measurements/bodyweight'),
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
/// sparkline, chevron. Tapping opens the real chart elsewhere.
class _TrendPreviewCard extends StatelessWidget {
  const _TrendPreviewCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.spots,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final List<FlSpot>? spots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final hasData = spots != null && spots!.any((s) => s.y > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: HxCard(
        accent: accent,
        onTap: () {
          Haptics.selection();
          onTap();
        },
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
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.secondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: hx.secondary),
              ],
            ),
            const SizedBox(height: HxSpace.x2),
            SizedBox(
              height: 56,
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
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData:
                            const LineTouchData(enabled: false),
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
      ),
    );
  }
}
