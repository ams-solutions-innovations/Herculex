import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../../profile/domain/profile.dart';
import '../domain/daily_totals.dart';
import 'nutrition_providers.dart';
import 'widgets/macro_chart.dart';

/// Dedicated Trend view for any macro ('kcal', 'protein', 'carbs', 'fat').
/// Displays 7-day average, target comparison, interactive line chart (7D/30D/90D),
/// range statistics (best/worst compliance), and macro-specific insights.
class MacroTrendView extends ConsumerStatefulWidget {
  const MacroTrendView({super.key, this.macro = 'kcal'});

  final String macro;

  @override
  ConsumerState<MacroTrendView> createState() => _MacroTrendViewState();
}

class _MacroTrendViewState extends ConsumerState<MacroTrendView> {
  static const _ranges = [('7D', '1W'), ('30D', '1M'), ('90D', '3M')];

  String _range = '7D';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final macro = widget.macro;

    final avg = ref.watch(averageWeeklyMacroProvider(macro));
    final avgKcal = ref.watch(averageWeeklyCaloriesProvider);
    final historyAsync = ref.watch(nutritionHistoryProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targets = ref.watch(effectiveTargetsProvider(today)).asData?.value;
    final target = macroTargetFor(targets, macro);

    final rangeStats = historyAsync.asData?.value == null
        ? null
        : _RangeStats.compute(historyAsync.asData!.value, macro, _range, target);

    final title = _titleFor(macro);
    final accent = _accentFor(macro, hx);
    final unit = macro == 'kcal' ? 'kcal' : 'g';
    final dailyUnit = macro == 'kcal' ? 'kcal/day' : 'g/day';

    return HxScreenShell(
      title: title,
      children: [
        // ── 1. 7-Day Average Header Card ──
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.14),
                hx.surfaceContainerLowest,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(HxSpace.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVG DAILY ${_macroName(macro).toUpperCase()} · LAST 7 DAYS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: HxSpace.x1),
              Text(
                avg == null ? '—' : '${avg.round()} $dailyUnit',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (target != null && avg != null) ...[
                const SizedBox(height: HxSpace.x1),
                Text(
                  _vsTargetLabel(avg, target, macro),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: HxSpace.x2),
              Text(
                _descriptionFor(macro),
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: HxSpace.x4),

        // ── 2. Interactive Chart Card ──
        HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_macroName(macro).toUpperCase()} TREND',
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
                  macro: macro,
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

        // ── 3. Range Statistics Card ──
        if (rangeStats != null && rangeStats.daysLogged > 0) ...[
          const SizedBox(height: HxSpace.x4),
          HxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${rangeStats.daysLogged} of ${rangeStats.totalDays} days logged in range',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Avg: ${rangeStats.avgValue.round()} $unit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                if (rangeStats.best != null) ...[
                  const SizedBox(height: HxSpace.x3),
                  _dayStatRow(
                    context,
                    label: 'Closest to target',
                    day: rangeStats.best!,
                    unit: unit,
                    accent: hx.success,
                  ),
                ],
                if (rangeStats.worst != null) ...[
                  const SizedBox(height: HxSpace.x2),
                  _dayStatRow(
                    context,
                    label: 'Furthest from target',
                    day: rangeStats.worst!,
                    unit: unit,
                    accent: hx.warning,
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── 4. Macro-Specific Insights & Distribution Card ──
        if (avg != null) ...[
          const SizedBox(height: HxSpace.x4),
          _MacroInsightCard(
            macro: macro,
            avg: avg,
            avgKcal: avgKcal,
            target: target,
            profile: profile,
            accent: accent,
          ),
        ],

        // ── 5. Adjust Goals Button ──
        const SizedBox(height: HxSpace.x4),
        InkWell(
          onTap: () => context.push('/calorie-macro-goals'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 18, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Adjust $title Goals',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: hx.secondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x6),
      ],
    );
  }

  Widget _dayStatRow(
    BuildContext context, {
    required String label,
    required _DayMacroVal day,
    required String unit,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: HxSpace.x2),
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
        ),
        Text(
          '${DateFormat('MMM d').format(day.date)} · ${day.value.round()} $unit',
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _titleFor(String macro) => switch (macro) {
        'protein' => 'Protein Trends',
        'carbs' => 'Carb Trends',
        'fat' => 'Fat Trends',
        _ => 'Calorie Trends',
      };

  String _macroName(String macro) => switch (macro) {
        'protein' => 'Protein',
        'carbs' => 'Carbs',
        'fat' => 'Fats',
        _ => 'Calories',
      };

  Color _accentFor(String macro, HxColors hx) => switch (macro) {
        'protein' => hx.macroProtein,
        'carbs' => hx.macroCarbs,
        'fat' => hx.isDark ? hx.macroFat : hx.macroFatText,
        _ => hx.domainNutrition,
      };

  String _descriptionFor(String macro) => switch (macro) {
        'protein' =>
          'The mean of your logged protein intake per day over the last 7 days. Essential for muscle repair, recovery, and hypertrophy.',
        'carbs' =>
          'The mean of your logged carbohydrate intake per day over the last 7 days. Powers glycogen storage and high-intensity performance.',
        'fat' =>
          'The mean of your logged healthy fats per day over the last 7 days. Crucial for hormonal balance, cellular health, and satiety.',
        _ =>
          'The mean of your logged calories per day over the last 7 days. Days without any logged food are skipped, so an unlogged day does not drag the average down.',
      };

  String _vsTargetLabel(double avg, double target, String macro) {
    if (avg.isNaN || target.isNaN) return '';
    final diff = (avg - target).round();
    final unit = macro == 'kcal' ? 'kcal' : 'g';
    if (diff == 0) return 'Exactly on your ${target.round()} $unit target.';
    final direction = diff > 0 ? 'above' : 'below';
    return '${diff.abs()} $unit/day $direction your ${target.round()} $unit target.';
  }
}

class _DayMacroVal {
  const _DayMacroVal(this.date, this.value);
  final DateTime date;
  final double value;
}

class _RangeStats {
  const _RangeStats({
    required this.totalDays,
    required this.daysLogged,
    required this.avgValue,
    this.best,
    this.worst,
  });

  final int totalDays;
  final int daysLogged;
  final double avgValue;
  final _DayMacroVal? best;
  final _DayMacroVal? worst;

  static _RangeStats compute(
    Map<String, DailyTotals> historyMap,
    String macro,
    String range,
    double? target,
  ) {
    final days = macroDaysForRange(range);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final logged = <_DayMacroVal>[];
    double sum = 0;
    for (var i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final iso = DateFormat('yyyy-MM-dd').format(date);
      final totals = historyMap[iso];
      if (totals != null) {
        final val = macroValueForTotals(totals, macro);
        if (val > 0 && !val.isNaN && !val.isInfinite) {
          logged.add(_DayMacroVal(date, val));
          sum += val;
        }
      }
    }

    final avg = logged.isNotEmpty ? sum / logged.length : 0.0;

    if (logged.isEmpty || target == null || target <= 0 || target.isNaN || target.isInfinite) {
      return _RangeStats(totalDays: days, daysLogged: logged.length, avgValue: avg);
    }

    final byCloseness = [...logged]
      ..sort((a, b) =>
          (a.value - target).abs().compareTo((b.value - target).abs()));

    return _RangeStats(
      totalDays: days,
      daysLogged: logged.length,
      avgValue: avg,
      best: byCloseness.first,
      worst: byCloseness.length > 1 ? byCloseness.last : null,
    );
  }
}

class _MacroInsightCard extends StatelessWidget {
  const _MacroInsightCard({
    required this.macro,
    required this.avg,
    required this.avgKcal,
    required this.target,
    required this.profile,
    required this.accent,
  });

  final String macro;
  final double avg;
  final double? avgKcal;
  final double? target;
  final Profile? profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final bw = profile?.weightKg;
    final totalKcal = avgKcal ?? 0;

    if (macro == 'protein') {
      final perKg = (bw != null && bw > 0) ? (avg / bw) : null;
      final pctOfKcal = totalKcal > 0 ? ((avg * 4 / totalKcal) * 100).round() : null;

      return HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROTEIN DISTRIBUTION & INTAKE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.secondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: HxSpace.x3),
            Row(
              children: [
                if (perKg != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${perKg.toStringAsFixed(2)} g/kg',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                        Text('bodyweight', style: TextStyle(fontSize: 11, color: hx.secondary)),
                      ],
                    ),
                  ),
                if (pctOfKcal != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pctOfKcal%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                        Text('of daily calories', style: TextStyle(fontSize: 11, color: hx.secondary)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: HxSpace.x2),
            Text(
              'Recommended for athletes: 1.6 – 2.2 g/kg of bodyweight daily to maximize muscle protein synthesis and recovery.',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
          ],
        ),
      );
    }

    if (macro == 'carbs') {
      final pctOfKcal = totalKcal > 0 ? ((avg * 4 / totalKcal) * 100).round() : null;
      return HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CARBOHYDRATE FUEL DISTRIBUTION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.secondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: HxSpace.x3),
            if (pctOfKcal != null)
              Row(
                children: [
                  Text(
                    '$pctOfKcal%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('of total caloric energy', style: TextStyle(fontSize: 12, color: hx.secondary)),
                ],
              ),
            const SizedBox(height: HxSpace.x2),
            Text(
              'Carbohydrates replenish intramuscular glycogen stores. Higher intake on training days supports peak anaerobic power and training volume.',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
          ],
        ),
      );
    }

    if (macro == 'fat') {
      final pctOfKcal = totalKcal > 0 ? ((avg * 9 / totalKcal) * 100).round() : null;
      return HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DIETARY FAT & HORMONAL HEALTH',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.secondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: HxSpace.x3),
            if (pctOfKcal != null)
              Row(
                children: [
                  Text(
                    '$pctOfKcal%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('of total caloric energy', style: TextStyle(fontSize: 12, color: hx.secondary)),
                ],
              ),
            const SizedBox(height: HxSpace.x2),
            Text(
              'Healthy dietary fats (20% – 35% of total calories) are required for steroid hormone synthesis (testosterone), joint lubrication, and fat-soluble vitamin absorption.',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
