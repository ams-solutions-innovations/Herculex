import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../../ui/ui.dart';
import '../../../nutrition/domain/daily_totals.dart';
import '../../../nutrition/domain/macro_targets.dart';
import '../../domain/macro_card_config.dart';
import '../macro_card_prefs_provider.dart';

/// Live calorie/macro grid: a config-driven grid of macro tiles.
/// Full weekly stats & average daily intake live in the Calorie Trends view.
class LiveMacrosGrid extends ConsumerWidget {
  final DailyTotals totals;
  final MacroTargets? targets;
  const LiveMacrosGrid({
    super.key,
    required this.totals,
    required this.targets,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = targets;
    final macroConfig = ref.watch(macroCardPrefsProvider);
    final visible = macroConfig.visibleMacros;

    if (visible.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        for (final macro in visible) _tileFor(macro, totals, t, context),
      ],
    );
  }

  Widget _tileFor(
    DashboardMacro macro,
    DailyTotals totals,
    MacroTargets? t,
    BuildContext context,
  ) {
    return switch (macro) {
      DashboardMacro.kcal => HxStatTile(
        label: 'CALORIES',
        icon: Icons.local_fire_department,
        accent: AppColors.macroKcal,
        value: totals.kcal.round().toString(),
        secondaryValue: t == null ? null : '/ ${t.kcal} kcal',
        progress: t == null ? null : totals.kcal / t.kcal,
        onTap: () {
          Haptics.selection();
          context.push('/nutrition/weekly-stats');
        },
      ),
      DashboardMacro.protein => HxStatTile(
        label: 'PROTEIN',
        icon: Icons.egg_alt,
        accent: AppColors.macroProtein,
        value: '${totals.proteinG.round()}g',
        secondaryValue: t == null ? null : '/ ${t.proteinG}g',
        progress: t == null ? null : totals.proteinG / t.proteinG,
        onTap: () {
          Haptics.selection();
          context.push('/macro-trends/protein');
        },
      ),
      DashboardMacro.carbs => HxStatTile(
        label: 'CARBS',
        icon: Icons.bakery_dining,
        accent: AppColors.macroCarbs,
        value: '${totals.carbsG.round()}g',
        secondaryValue: t == null ? null : '/ ${t.carbsG}g',
        progress: t == null ? null : totals.carbsG / t.carbsG,
        onTap: () {
          Haptics.selection();
          context.push('/macro-trends/carbs');
        },
      ),
      DashboardMacro.fat => HxStatTile(
        label: 'FATS',
        icon: Icons.water_drop,
        accent: AppColors.macroFat,
        iconColor: AppColors.macroFatText,
        value: '${totals.fatG.round()}g',
        secondaryValue: t == null ? null : '/ ${t.fatG}g',
        progress: t == null ? null : totals.fatG / t.fatG,
        onTap: () {
          Haptics.selection();
          context.push('/macro-trends/fat');
        },
      ),
    };
  }
}
