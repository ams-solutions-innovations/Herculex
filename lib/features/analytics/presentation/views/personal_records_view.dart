import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/data/analytics_repository.dart';

/// Every exercise's best estimated 1RM, strongest first. Opened from the
/// "Latest PRs" dashboard card; tapping a row opens that exercise.
class PersonalRecordsView extends ConsumerWidget {
  const PersonalRecordsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = ref.watch(allOneRmsProvider);
    final hx = context.hx;

    return HxScreenShell(
      title: 'Personal Records',
      titleIcon: Icons.emoji_events_outlined,
      children: [
        prs.when(
          data: (list) => list.isEmpty
              ? const _EmptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Summary(list: list),
                    const SizedBox(height: HxSpace.x4),
                    for (var i = 0; i < list.length; i++) ...[
                      _PrRow(rank: i + 1, pr: list[i]),
                      const SizedBox(height: HxSpace.x2),
                    ],
                  ],
                ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(HxSpace.x6),
            child: Text(
              'Failed to load records: $e',
              style: TextStyle(color: hx.danger),
            ),
          ),
        ),
      ],
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.list});

  final List<OneRmProjection> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final best = list.first;
    final weight = ref.watch(weightFormatProvider);

    return HxCard(
      accent: hx.domainTraining,
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: hx.domainTraining, size: 32),
          const SizedBox(width: HxSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STRONGEST LIFT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  best.exerciseName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${weight.format(best.estimatedOneRmKg, decimals: 0)} est. 1RM · '
                  '${list.length} exercises tracked',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrRow extends ConsumerWidget {
  const _PrRow({required this.rank, required this.pr});

  final int rank;
  final OneRmProjection pr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      onTap: () {
        Haptics.selection();
        context.push(AppPaths.exercise(pr.exerciseId));
      },
      padding: const EdgeInsets.symmetric(
        horizontal: HxSpace.x4,
        vertical: HxSpace.x3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: theme.textTheme.labelLarge?.copyWith(
                color: rank <= 3
                    ? hx.domainTraining
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              pr.exerciseName,
              style: theme.textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: HxSpace.x2),
          Text(
            ref
                .watch(weightFormatProvider)
                .format(pr.estimatedOneRmKg, decimals: 0),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: HxSpace.x1),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x8),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HxSpace.x3),
          Text('No PRs yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Finish a workout with loaded sets and your best lifts show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
