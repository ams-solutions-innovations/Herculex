import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import '../../../analytics/presentation/widgets/muscle_recovery_row.dart';
import 'dashboard_shared.dart';
/// Compact recovery overview (§18) reusing the Phase-3 19-group engine: shows
/// the most-fatigued groups.
class RecoverySummaryCard extends ConsumerWidget {
  const RecoverySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryV3Provider);

    return dashboardCard(
      accent: context.hx.domainRecovery,
      onTap: () => context.push('/recovery'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dashboardTitle(context, 'Recovery'),
          const SizedBox(height: 12),
          recovery.when(
            data: (groups) {
              final sorted = [...groups]
                ..sort((a, b) => a.recoveryScore.compareTo(b.recoveryScore));
              final worst = sorted.take(4).toList();
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
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
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
          radius: isCompact ? 20 : 999,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 24,
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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CNS LOAD',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: context.hx.secondary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        Icon(Icons.bolt_outlined, size: 16, color: color),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${(t.readiness * 100).round()}%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(
                                alpha: context.hx.isDark ? 0.20 : 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t.status,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: color,
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
                    children: [
                      Text('${(t.readiness * 100).round()}%',
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold, color: color)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: color.withValues(
                                alpha: context.hx.isDark ? 0.20 : 0.12),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(t.status,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color)),
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
