import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/measurements/presentation/quick_log_weight.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:intl/intl.dart';

/// Latest bodyweight reading (§18) with quick add. The trend chart that used
/// to live inline moved to the swipeable [TrendCardsRow] and the full
/// `/measurements/bodyweight` page — tapping the card opens that trend
/// (UI-rework P4).
class BodyweightMiniCard extends ConsumerWidget {
  const BodyweightMiniCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bw = ref.watch(latestBodyweightProvider);
    final history = ref.watch(bodyweightHistoryProvider).asData?.value;
    final lastLogged = history == null || history.isEmpty
        ? null
        : DateTime.tryParse(history.last.dateIso);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return dashboardCard(
          accent: context.hx.domainRecovery,
          onTap: () {
            Haptics.selection();
            context.push('/measurements/bodyweight');
          },
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: isCompact ? 12 : 16,
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'BODYWEIGHT',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => quickLogWeight(context, ref),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    bw.when(
                      data: (kg) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          kg == null
                              ? '—'
                              : ref.watch(weightFormatProvider).format(kg),
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
                    if (lastLogged != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d').format(lastLogged),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          dashboardTitle(context, 'Bodyweight'),
                          if (lastLogged != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Last logged ${DateFormat('MMM d').format(lastLogged)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    bw.when(
                      data: (kg) => Text(
                        kg == null
                            ? '—'
                            : ref.watch(weightFormatProvider).format(kg),
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
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      tooltip: 'Quick add bodyweight',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => quickLogWeight(context, ref),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
