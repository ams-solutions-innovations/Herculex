import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/units.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../workouts/presentation/workouts_providers.dart';
import '../../../measurements/presentation/quick_log_weight.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';

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

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        Haptics.selection();
        context.push('/measurements/bodyweight');
      },
      child: dashboardCard(
        child: Row(
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ],
              ),
            ),
            bw.when(
              data: (kg) => Text(
                kg == null ? '—' : ref.watch(weightFormatProvider).format(kg),
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
              error: (e, _) => const Icon(Icons.error_outline, size: 18),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.add_circle_outline,
                  color: AppColors.primary, size: 22),
              tooltip: 'Quick add bodyweight',
              visualDensity: VisualDensity.compact,
              onPressed: () => quickLogWeight(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
