import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/colors.dart';
import '../../../health/domain/cycle_adjuster.dart';
import '../../../health/presentation/cycle_providers.dart';
/// Cycle-phase focus card (§18). Live reactive card showing current phase,
/// physiological recommendations, volume adjustments, and tap to view cycle tracker.
class CycleFocusCard extends ConsumerWidget {
  const CycleFocusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adjustmentAsync = ref.watch(cycleAdjustmentProvider);

    return adjustmentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (adjustment) {
        final phase = adjustment.phase;
        Color phaseColor;
        switch (phase) {
          case CyclePhase.menstrual:
            phaseColor = Colors.redAccent;
            break;
          case CyclePhase.follicular:
            phaseColor = Colors.orangeAccent;
            break;
          case CyclePhase.ovulatory:
            phaseColor = Colors.purpleAccent;
            break;
          case CyclePhase.luteal:
            phaseColor = AppColors.primary;
            break;
        }

        return InkWell(
          onTap: () => context.push('/cycle'),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: phaseColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: phaseColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(phase.icon, color: phaseColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            phase.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: phaseColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              adjustment.isManualOverride
                                  ? 'OVERRIDE'
                                  : 'DAY ${adjustment.dayOfCycle + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: phaseColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adjustment.trainingRecommendation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            adjustment.statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: phaseColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Track & Sync ›',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: phaseColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
