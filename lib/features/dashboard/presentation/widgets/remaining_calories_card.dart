import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../shell/main_scaffold.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';

/// Calories left today (§18): `Goal - Food + Exercise`. Tapping opens the
/// nutrition tab. Styled with adaptive layout for full-width and half-width grid slots.
class RemainingCaloriesCard extends ConsumerWidget {
  const RemainingCaloriesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final r = ref.watch(remainingCaloriesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        if (r == null) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.macroKcal.withValues(alpha: 0.10),
                  hx.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.macroKcal.withValues(alpha: 0.25),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push('/nutrition-targets'),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 14 : 20,
                    vertical: isCompact ? 14 : 16,
                  ),
                  child: isCompact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'REMAINING',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.secondary,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Set a goal',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColors.macroKcal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: dashboardTitle(context, 'Remaining'),
                            ),
                            Text(
                              'Set a goal',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.secondary),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        }

        final color = r.isOver ? Colors.redAccent : AppColors.macroKcal;

        if (isCompact) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.12),
                  hx.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              r.isOver ? 'OVER BUDGET' : 'REMAINING',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: hx.secondary,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              r.isOver
                                  ? Icons.warning_amber_rounded
                                  : Icons.local_fire_department,
                              size: 16,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${r.remaining.abs()}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'kcal',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hx.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: r.consumedFraction.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor:
                              AppColors.surfaceVariant.withValues(alpha: 0.5),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${r.food} / ${r.goal} kcal',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hx.secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                hx.surfaceContainerLowest,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: dashboardTitle(
                            context,
                            r.isOver ? 'Over budget' : 'Calories Remaining',
                          ),
                        ),
                        Text(
                          '${r.remaining.abs()}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'kcal',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.secondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: r.consumedFraction.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            AppColors.surfaceVariant.withValues(alpha: 0.5),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _term(theme, 'Goal', r.goal, AppColors.secondary),
                        _op(theme, '−'),
                        _term(theme, 'Food', r.food, AppColors.macroProtein),
                        _op(theme, '+'),
                        _term(
                          theme,
                          'Exercise',
                          r.exercise,
                          AppColors.brightness == Brightness.dark
                              ? const Color(0xFF30D158)
                              : const Color(0xFF34C759),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _term(ThemeData theme, String label, int value, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontSize: 9,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$value',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      );

  Widget _op(ThemeData theme, String symbol) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            ' ',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              symbol,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
}
