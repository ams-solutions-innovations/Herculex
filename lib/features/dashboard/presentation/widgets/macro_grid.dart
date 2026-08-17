import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../../ui/ui.dart';
import '../../../../widgets/app_bottom_sheet.dart';
import '../../../nutrition/domain/daily_totals.dart';
import '../../../nutrition/domain/macro_targets.dart';
import '../../../nutrition/presentation/nutrition_providers.dart';
import '../../domain/macro_card_config.dart';
import '../macro_card_prefs_provider.dart';

/// Live calorie/macro grid (§18): the Average Daily Intake banner plus a
/// config-driven grid of macro tiles. The trend chart that used to live below
/// the grid moved to the swipeable [TrendCardsRow] and the full weekly-stats
/// page — the dashboard shows numbers, not a chart to read (UI-rework P4).
class LiveMacrosGrid extends ConsumerWidget {
  final DailyTotals totals;
  final MacroTargets? targets;
  const LiveMacrosGrid({super.key, required this.totals, required this.targets});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = targets;
    final avgWeeklyKcal = ref.watch(averageWeeklyCaloriesProvider);
    final macroConfig = ref.watch(macroCardPrefsProvider);
    final visible = macroConfig.visibleMacros;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Average Daily Intake Banner ──
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            onTap: () {
              Haptics.selection();
              context.push('/nutrition/weekly-stats');
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_fire_department,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "AVG DAILY INTAKE · LAST 7 DAYS",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          avgWeeklyKcal == null
                              ? "—"
                              : "${avgWeeklyKcal.round()} kcal/day",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline,
                        size: 18, color: AppColors.secondary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showAvgIntakeExplainer(context),
                  ),
                  Icon(Icons.chevron_right,
                      size: 20, color: AppColors.secondary),
                ],
              ),
            ),
          ),
        ),

        // ── Config-driven macro grid ──
        if (visible.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              for (final macro in visible) _tileFor(macro, totals, t),
            ],
          ),
      ],
    );
  }

  Widget _tileFor(DashboardMacro macro, DailyTotals totals, MacroTargets? t) {
    return switch (macro) {
      DashboardMacro.kcal => HxStatTile(
          label: 'CALORIES',
          icon: Icons.local_fire_department,
          accent: AppColors.macroKcal,
          value: totals.kcal.round().toString(),
          secondaryValue: t == null ? null : '/ ${t.kcal}',
          progress: t == null ? null : totals.kcal / t.kcal,
        ),
      DashboardMacro.protein => HxStatTile(
          label: 'PROTEIN',
          icon: Icons.egg_alt,
          accent: AppColors.macroProtein,
          value: '${totals.proteinG.round()}g',
          secondaryValue: t == null ? null : '/ ${t.proteinG}g',
          progress: t == null ? null : totals.proteinG / t.proteinG,
        ),
      DashboardMacro.carbs => HxStatTile(
          label: 'CARBS',
          icon: Icons.bakery_dining,
          accent: AppColors.macroCarbs,
          value: '${totals.carbsG.round()}g',
          secondaryValue: t == null ? null : '/ ${t.carbsG}g',
          progress: t == null ? null : totals.carbsG / t.carbsG,
        ),
      DashboardMacro.fat => HxStatTile(
          label: 'FATS',
          icon: Icons.water_drop,
          accent: AppColors.macroFat,
          iconColor: AppColors.macroFatText,
          value: '${totals.fatG.round()}g',
          secondaryValue: t == null ? null : '/ ${t.fatG}g',
          progress: t == null ? null : totals.fatG / t.fatG,
        ),
    };
  }

  void _showAvgIntakeExplainer(BuildContext context) {
    AppBottomSheet.show(
      context,
      builder: (_) => AppBottomSheet(
        title: 'Average daily intake',
        scrollable: false,
        child: Text(
          'The mean of your logged calories per day over the last 7 days. '
          'Days without any logged food are skipped, so an unlogged day does '
          'not drag the average down. Tap the banner itself for weekly and '
          '3-month trends.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
