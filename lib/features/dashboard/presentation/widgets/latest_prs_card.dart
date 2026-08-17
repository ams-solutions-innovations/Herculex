import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/units.dart';
import '../../../../theme/colors.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import 'dashboard_shared.dart';
/// Latest estimated 1RM PRs (§18).
class LatestPrsCard extends ConsumerWidget {
  const LatestPrsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prs = ref.watch(topOneRmsProvider);
    return dashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dashboardTitle(context, 'Latest PRs'),
          const SizedBox(height: 12),
          prs.when(
            data: (list) => list.isEmpty
                ? Text('No PRs yet',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary))
                : Column(
                    children: [
                      for (final p in list.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(p.exerciseName,
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis)),
                              Text(ref.watch(weightFormatProvider).format(p.estimatedOneRmKg, decimals: 0),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
