import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../domain/daily_totals.dart';
import 'nutrition_providers.dart';
import 'widgets/macro_chart.dart';

/// Calorie-trends page behind the dashboard's avg-intake banner.
///
/// First adopter of [HxScreenShell]: the frosted back button and title hide
/// as you scroll into the charts and return the instant you scroll up.
class WeeklyCaloriesView extends ConsumerStatefulWidget {
  const WeeklyCaloriesView({super.key});

  @override
  ConsumerState<WeeklyCaloriesView> createState() => _WeeklyCaloriesViewState();
}

class _WeeklyCaloriesViewState extends ConsumerState<WeeklyCaloriesView> {
  static const _ranges = [('7D', '1W'), ('30D', '1M'), ('90D', '3M')];

  String _range = '7D';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final avg = ref.watch(averageWeeklyCaloriesProvider);
    final historyAsync = ref.watch(nutritionHistoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targets = ref.watch(effectiveTargetsProvider(today)).asData?.value;
    final target = macroTargetFor(targets, 'kcal');
    final rangeStats = historyAsync.asData?.value == null
        ? null
        : _RangeStats.compute(historyAsync.asData!.value, _range, target);

    return HxScreenShell(
      title: 'Calorie Trends',
      children: [
        HxCard(
          accent: hx.domainNutrition,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVG DAILY INTAKE · LAST 7 DAYS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: HxSpace.x1),
              Text(
                avg == null ? '—' : '${avg.round()} kcal/day',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: hx.domainNutrition),
              ),
              if (target != null && avg != null) ...[
                const SizedBox(height: HxSpace.x1),
                Text(
                  _vsTargetLabel(avg, target),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: HxSpace.x2),
              Text(
                'The mean of your logged calories per day over the last 7 '
                'days. Days without any logged food are skipped, so an '
                'unlogged day does not drag the average down.',
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CALORIE TREND',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.secondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Row(
                    children: [
                      for (final (range, label) in _ranges) ...[
                        HxTextPill(
                          label: label,
                          selected: _range == range,
                          onTap: () => setState(() => _range = range),
                        ),
                        if (range != _ranges.last.$1)
                          const SizedBox(width: HxSpace.x1 + 2),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: HxSpace.x4),
              historyAsync.when(
                data: (historyMap) => MacroTrendChart(
                  historyMap: historyMap,
                  macro: 'kcal',
                  range: _range,
                  targetValue: target,
                  height: 200,
                ),
                loading: () => const SizedBox(
                  height: 200,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Error loading trend: $e',
                        style: theme.textTheme.bodySmall),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (rangeStats != null && rangeStats.daysLogged > 0) ...[
          const SizedBox(height: HxSpace.x4),
          HxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rangeStats.daysLogged} of ${rangeStats.totalDays} days '
                  'logged in this range',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (rangeStats.best != null) ...[
                  const SizedBox(height: HxSpace.x3),
                  _dayStatRow(
                    context,
                    label: 'Closest to target',
                    day: rangeStats.best!,
                    accent: hx.success,
                  ),
                ],
                if (rangeStats.worst != null) ...[
                  const SizedBox(height: HxSpace.x2),
                  _dayStatRow(
                    context,
                    label: 'Furthest from target',
                    day: rangeStats.worst!,
                    accent: hx.warning,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dayStatRow(
    BuildContext context, {
    required String label,
    required _DayKcal day,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
        const SizedBox(width: HxSpace.x2),
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
        ),
        Text(
          '${DateFormat('MMM d').format(day.date)} · ${day.kcal.round()} kcal',
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _vsTargetLabel(double avg, double target) {
    final diff = (avg - target).round();
    if (diff == 0) return 'Exactly on your ${target.round()} kcal target.';
    final direction = diff > 0 ? 'above' : 'below';
    return '${diff.abs()} kcal/day $direction your '
        '${target.round()} kcal target.';
  }
}

class _DayKcal {
  const _DayKcal(this.date, this.kcal);
  final DateTime date;
  final double kcal;
}

/// Logged-days count plus, when a target exists, the day that landed closest
/// to and furthest from it over the selected range.
class _RangeStats {
  const _RangeStats({
    required this.totalDays,
    required this.daysLogged,
    this.best,
    this.worst,
  });

  final int totalDays;
  final int daysLogged;
  final _DayKcal? best;
  final _DayKcal? worst;

  static _RangeStats compute(
    Map<String, DailyTotals> historyMap,
    String range,
    double? target,
  ) {
    final days = macroDaysForRange(range);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final logged = <_DayKcal>[];
    for (var i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final iso = DateFormat('yyyy-MM-dd').format(date);
      final totals = historyMap[iso];
      if (totals != null && totals.kcal > 0) {
        logged.add(_DayKcal(date, totals.kcal));
      }
    }

    if (logged.isEmpty || target == null || target <= 0) {
      return _RangeStats(totalDays: days, daysLogged: logged.length);
    }

    final byCloseness = [...logged]
      ..sort((a, b) =>
          (a.kcal - target).abs().compareTo((b.kcal - target).abs()));

    return _RangeStats(
      totalDays: days,
      daysLogged: logged.length,
      best: byCloseness.first,
      worst: byCloseness.length > 1 ? byCloseness.last : null,
    );
  }
}
