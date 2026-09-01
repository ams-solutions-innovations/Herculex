import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import 'dashboard_shared.dart';

/// This week's total volume mini-card (§18). Tapping navigates to the dedicated
/// Muscle Volume Overview page.
class WeeklyVolumeMiniCard extends ConsumerWidget {
  const WeeklyVolumeMiniCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final volume = ref.watch(weeklyMuscleVolumeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return DashboardPill(
          color: context.hx.domainTraining,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: isCompact ? 12 : 16,
          ),
          onTap: () {
            Haptics.selection();
            context.push('/muscle-volume');
          },
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TOTAL VOLUME',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    volume.when(
                      data: (v) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${v.totalSets} sets',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (e, _) =>
                          const Icon(Icons.error_outline, size: 18),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: dashboardTitle(context, 'Total Volume')),
                    volume.when(
                      data: (v) => Text(
                        '${v.totalSets} sets',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (e, _) =>
                          const Icon(Icons.error_outline, size: 18),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
        );
      },
    );
  }
}
