import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import 'dashboard_shared.dart';
/// Compact recovery overview (§18) reusing the Phase-3 19-group engine: shows
/// the most-fatigued groups.
class RecoverySummaryCard extends ConsumerWidget {
  const RecoverySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recovery = ref.watch(recoveryV3Provider);

    return dashboardCard(
      onTap: () => context.push('/insights'),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 92,
                              child: Text(g.muscle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                              )),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: g.recoveryScore / 100,
                                minHeight: 8,
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
                          SizedBox(
                              width: 36,
                              child: Text('${g.recoveryScore}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary))),
                        ],
                      ),
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
    return DashboardPill(
      onTap: () => context.push('/insights'),
      child: Row(
        children: [
          Expanded(child: dashboardTitle(context, 'CNS Load')),
          cns.when(
            data: (t) {
              final color = switch (t.status) {
                'FRESH' => Colors.green,
                'MODERATE' => Colors.amber,
                _ => Colors.red,
              };
              return Row(
                children: [
                  Text('${(t.readiness * 100).round()}%',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(t.status,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              );
            },
            loading: () => const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => const Icon(Icons.error_outline, size: 18),
          ),
        ],
      ),
    );
  }
}
