part of '../profile_view.dart';

/// Training level summary on the profile; taps through to the level screen.
class _ProfileLevelCard extends ConsumerWidget {
  const _ProfileLevelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progressAsync = ref.watch(levelProgressProvider);
    return progressAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (progress) {
        final level = progress.level;
        final next = progress.nextLevel;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              Haptics.selection();
              context.push(AppRoutes.trainingLevel);
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.military_tech_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Training level',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        level.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary.withValues(alpha: 0.8),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${progress.completedWorkouts} workouts logged',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const _PercentileLine(),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress.progressToNext,
                      minHeight: 8,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.16,
                      ),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        next != null
                            ? 'Next: ${next.title}'
                            : level.band.next == null
                            ? 'Top rank reached'
                            : 'Strength unlocks ${level.band.next!.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'View Details',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Squat: top 10% of lifters · top 2% worldwide". Rotates daily through the
/// lifts in the top half; hidden until a benchmark lift is logged.
class _PercentileLine extends ConsumerWidget {
  const _PercentileLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(strengthPercentilesProvider).valueOrNull;
    final today = ref.watch(clockProvider).now();
    final p = all == null ? null : StrengthPercentiles.highlight(all, today);
    if (p == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hx = context.hx;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${p.lift.label}: top ${formatTopPct(p.lifterTopPct)} ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: 'of lifters'),
            TextSpan(
              text: ' · top ${formatTopPct(p.worldTopPct)} worldwide (est.)',
              style: TextStyle(color: hx.onSurfaceVariant),
            ),
          ],
        ),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
