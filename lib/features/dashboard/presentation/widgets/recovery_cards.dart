import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/presentation/analytics_providers.dart';
import 'package:herculex/features/analytics/presentation/widgets/muscle_recovery_row.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';

/// Compact recovery overview (§18) reusing the Phase-3 19-group engine: shows
/// the most-fatigued groups with responsive layouts for full-width and half-width tiles.
class RecoverySummaryCard extends ConsumerWidget {
  const RecoverySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recovery = ref.watch(recoveryV3Provider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return dashboardCard(
          accent: context.hx.domainRecovery,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: isCompact ? 12 : 16,
          ),
          onTap: () => context.push('/recovery'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isCompact ? 'RECOVERY' : 'Recovery',
                      style: isCompact
                          ? theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.battery_charging_full_outlined,
                    size: isCompact ? 16 : 20,
                    color: context.hx.domainRecovery,
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 8 : 12),
              recovery.when(
                data: (groups) {
                  final sorted = [
                    ...groups,
                  ]..sort((a, b) => a.recoveryScore.compareTo(b.recoveryScore));
                  final count = isCompact ? 3 : 4;
                  final worst = sorted.take(count).toList();

                  if (worst.isEmpty) {
                    return Text(
                      'All muscles recovered',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    );
                  }

                  if (isCompact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final g in worst)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    g.muscle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: (g.recoveryScore / 100).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      minHeight: 5,
                                      backgroundColor: AppColors.outlineVariant
                                          .withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation(
                                        g.recoveryScore >= 70
                                            ? Colors.green
                                            : g.recoveryScore >= 30
                                            ? Colors.amber
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${g.recoveryScore}',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      for (final g in worst)
                        MuscleRecoveryRow(
                          muscle: g.muscle,
                          recoveryScore: g.recoveryScore,
                        ),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (e, _) =>
                    Text('Error: $e', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// CNS readiness mini-card (§18).
class CnsLoadMiniCard extends ConsumerWidget {
  const CnsLoadMiniCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cns = ref.watch(cnsTrendsProvider);
    final accent = context.hx.domainRecovery;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return DashboardPill(
          color: accent,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: isCompact ? 12 : 16,
          ),
          onTap: () => context.push('/cns'),
          child: cns.when(
            data: (t) {
              final color = switch (t.status) {
                'FRESH' => context.hx.success,
                'MODERATE' => context.hx.warning,
                _ => context.hx.danger,
              };

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'CNS LOAD',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: context.hx.secondary,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.bolt_outlined, size: 16, color: color),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${(t.readiness * 100).round()}%',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: context.hx.isDark ? 0.20 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              t.status,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: dashboardTitle(context, 'CNS Load')),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(t.readiness * 100).round()}%',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: context.hx.isDark ? 0.20 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t.status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const SizedBox(
              height: 20,
              width: 20,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => const Icon(Icons.error_outline, size: 18),
          ),
        );
      },
    );
  }
}
