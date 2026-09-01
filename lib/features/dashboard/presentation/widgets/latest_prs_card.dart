import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/presentation/analytics_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';

/// Latest estimated 1RM PRs (§18).
class LatestPrsCard extends ConsumerWidget {
  const LatestPrsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prs = ref.watch(topOneRmsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return dashboardCard(
          accent: context.hx.domainTraining,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: isCompact ? 12 : 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isCompact ? 'LATEST PRS' : 'Latest PRs',
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
                    Icons.emoji_events_outlined,
                    size: isCompact ? 16 : 20,
                    color: context.hx.domainTraining,
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 8 : 12),
              prs.when(
                data: (list) => list.isEmpty
                    ? Text(
                        'No PRs yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final p in list.take(isCompact ? 2 : 3))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.exerciseName,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontSize: isCompact ? 12 : null,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    ref
                                        .watch(weightFormatProvider)
                                        .format(
                                          p.estimatedOneRmKg,
                                          decimals: 0,
                                        ),
                                    style:
                                        (isCompact
                                                ? theme.textTheme.bodyMedium
                                                : theme.textTheme.titleSmall)
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
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
