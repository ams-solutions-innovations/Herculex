import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../supplements/domain/supplement_intake.dart';
import '../../supplements/presentation/supplement_providers.dart';
import '../domain/daily_totals.dart';
import '../domain/food_insights.dart';
import '../domain/macro_targets.dart';
import '../domain/nutrient_definitions.dart';
import 'nutrition_providers.dart';

/// Full graphical breakdown of everything eaten on the selected day (§3):
/// the energy split, macros against target, and every tracked nutrient with
/// its share of the reference intake.
class NutrientOverviewView extends ConsumerWidget {
  const NutrientOverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = ref.watch(selectedDateProvider);
    final foodTotals =
        ref.watch(dailyTotalsProvider(date)).asData?.value ?? DailyTotals.empty;
    final targets = ref.watch(effectiveTargetsProvider(date)).asData?.value ??
        ref.watch(baselineTargetsProvider);

    // Supplement doses count towards micronutrients (§4), but only for today —
    // the taken-set is stored per day and pruned after a week.
    final now = ref.watch(clockProvider).now();
    final isToday =
        DateUtils.isSameDay(date, DateTime(now.year, now.month, now.day));
    final intake = isToday
        ? ref.watch(supplementIntakeTodayProvider)
        : SupplementIntake.empty;
    final totals = intake.nutrients.isEmpty
        ? foodTotals
        : foodTotals.plus(micros: intake.nutrients);

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Nutrient overview'),
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: totals.kcal <= 0 && intake.nutrients.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing logged on ${DateFormat('EEE, MMM d').format(date)} yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.secondary),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(DateFormat('EEEE, d MMMM').format(date),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.secondary)),
                const SizedBox(height: 20),
                _EnergySplitCard(totals: totals, targets: targets),
                const SizedBox(height: 20),
                _SectionTitle('Macronutrients'),
                const SizedBox(height: 10),
                _MacroBars(totals: totals, targets: targets),
                const SizedBox(height: 24),
                _SectionTitle('Micronutrients'),
                const SizedBox(height: 4),
                Text(
                  intake.nutrients.isEmpty
                      ? 'Shown as a share of the daily reference intake. Bars '
                          'are capped at 100%; foods without data contribute '
                          'nothing.'
                      : 'Includes today\'s ticked supplements. Shown as a '
                          'share of the daily reference intake.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondary),
                ),
                if (intake.untrackedNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${intake.untrackedNames.join(', ')} '
                    '${intake.untrackedNames.length == 1 ? 'has' : 'have'} no '
                    'per-dose nutrients set, so nothing is counted for '
                    '${intake.untrackedNames.length == 1 ? 'it' : 'them'}.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary),
                  ),
                ],
                const SizedBox(height: 12),
                _NutrientBars(totals: totals),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

/// Donut-free energy split: a single stacked bar plus the three shares, which
/// reads more precisely than a pie at this size.
class _EnergySplitCard extends StatelessWidget {
  final DailyTotals totals;
  final MacroTargets? targets;

  const _EnergySplitCard({required this.totals, required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = MacroSplit.fromGrams(
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text('ENERGY',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary, letterSpacing: 1.2)),
              ),
              Text('${totals.kcal.round()}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.macroKcal)),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                    targets == null ? 'kcal' : 'of ${targets!.kcal} kcal',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 12,
              // A day with no food (supplements only) has no split to draw —
              // an empty track reads better than three zero-width segments.
              child: split.totalKcal <= 0
                  ? ColoredBox(color: AppColors.surfaceVariant)
                  : Row(
                      children: [
                        Expanded(
                          flex:
                              (split.proteinShare * 1000).round().clamp(0, 1000),
                          child: ColoredBox(color: AppColors.macroProtein),
                        ),
                        Expanded(
                          flex: (split.carbsShare * 1000).round().clamp(0, 1000),
                          child: ColoredBox(color: AppColors.macroCarbs),
                        ),
                        Expanded(
                          flex: (split.fatShare * 1000).round().clamp(0, 1000),
                          child: ColoredBox(color: AppColors.macroFat),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _legend(theme, 'Protein', split.proteinShare,
                  AppColors.macroProtein),
              _legend(theme, 'Carbs', split.carbsShare, AppColors.macroCarbs),
              _legend(theme, 'Fat', split.fatShare, AppColors.macroFat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(ThemeData theme, String label, double share, Color color) =>
      Expanded(
        child: Row(
          children: [
            Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text('$label ${(share * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _MacroBars extends StatelessWidget {
  final DailyTotals totals;
  final MacroTargets? targets;

  const _MacroBars({required this.totals, required this.targets});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _NutrientBar(
          label: 'Protein',
          value: totals.proteinG,
          target: targets?.proteinG.toDouble(),
          unit: 'g',
          color: AppColors.macroProtein,
        ),
        _NutrientBar(
          label: 'Carbohydrate',
          value: totals.carbsG,
          target: targets?.carbsG.toDouble(),
          unit: 'g',
          color: AppColors.macroCarbs,
        ),
        _NutrientBar(
          label: 'Fat',
          value: totals.fatG,
          target: targets?.fatG.toDouble(),
          unit: 'g',
          color: AppColors.macroFat,
        ),
      ],
    );
  }
}

class _NutrientBars extends StatelessWidget {
  final DailyTotals totals;
  const _NutrientBars({required this.totals});

  /// Resolves a tracked nutrient's total, preferring the dedicated column
  /// where one exists and falling back to the free-form micros map.
  double? _valueFor(NutrientDefinition d) => switch (d.id) {
        'fiber' => totals.fiberG > 0 ? totals.fiberG : totals.nutrient('fiber'),
        'sodium' =>
          totals.sodiumMg > 0 ? totals.sodiumMg : totals.nutrient('sodium'),
        'potassium' => totals.potassiumMg > 0
            ? totals.potassiumMg
            : totals.nutrient('potassium'),
        'cholesterol' => totals.cholesterolMg > 0
            ? totals.cholesterolMg
            : totals.nutrient('cholesterol'),
        _ => totals.nutrient(d.id),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      for (final d in trackedNutrients)
        if ((_valueFor(d) ?? 0) > 0) (d, _valueFor(d)!),
    ];

    if (rows.isEmpty) {
      return Text(
        'None of today\'s foods carry micronutrient data.',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
      );
    }

    return Column(
      children: [
        for (final (d, value) in rows)
          _NutrientBar(
            label: d.label,
            value: value,
            target: d.dailyTarget,
            unit: d.unit,
            color: AppColors.primary,
          ),
      ],
    );
  }
}

class _NutrientBar extends StatelessWidget {
  final String label;
  final double value;
  final double? target;
  final String unit;
  final Color color;

  const _NutrientBar({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = target;
    final pct = t == null || t <= 0 ? null : value / t;
    // Exceeding a reference intake isn't automatically bad, but it's worth
    // flagging, so over-target bars switch colour rather than just filling.
    final over = pct != null && pct > 1;
    final barColor = over ? Colors.orangeAccent : color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '${_fmt(value)} $unit'
                '${t == null ? '' : ' / ${_fmt(t)} $unit'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary),
              ),
              if (pct != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text('${(pct * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold, color: barColor)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (pct ?? 0).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
}
