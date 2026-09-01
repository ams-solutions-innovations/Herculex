import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../../analytics/domain/muscle_recovery_v3.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../analytics/presentation/widgets/muscle_recovery_row.dart';
import '../domain/deload_urgency.dart';
import '../domain/muscle_deload_advisor.dart';
import 'recovery_providers.dart';
import 'widgets/joint_pain_selector.dart';
import 'widgets/recovery_header_card.dart';
import 'widgets/next_workout_suggestion_card.dart';

/// The dedicated Recovery page: overall readiness, a joint-pain selector,
/// next workout's training suggestion, and the full 19-muscle-group breakdown with
/// hours-until-recovered and deload flags — replacing the dashboard
/// Recovery card's old deep link into the general Insights page.
class RecoveryView extends StatelessWidget {
  const RecoveryView({super.key});

  @override
  Widget build(BuildContext context) {
    return const HxScreenShell(
      title: 'Recovery',
      children: [
        RecoveryHeaderCard(),
        SizedBox(height: HxSpace.x4),
        JointPainSelector(),
        SizedBox(height: HxSpace.x4),
        NextWorkoutSuggestionCard(),
        SizedBox(height: HxSpace.x4),
        _MuscleListCard(),
      ],
    );
  }
}

class _MuscleListCard extends ConsumerWidget {
  const _MuscleListCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final recovery = ref.watch(recoveryV3Provider);
    // ETA and deload are progressive enhancement on top of the score list:
    // each renders as soon as it resolves rather than blocking the whole
    // card on whichever of the three providers is slowest.
    final etaMap = ref.watch(recoveryEtaProvider).valueOrNull;
    final deloadSignals = ref.watch(muscleDeloadSignalsProvider).valueOrNull;
    final deloadByMuscle = {
      for (final s in deloadSignals ?? const <MuscleDeloadSignal>[])
        s.muscle: s.urgency,
    };

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MUSCLE GROUPS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x3),
          recovery.when(
            data: (groups) => Column(
              children: [
                for (final g in groups)
                  MuscleRecoveryRow(
                    muscle: g.muscle,
                    recoveryScore: g.recoveryScore,
                    etaLabel: etaMap == null
                        ? null
                        : _formatEta(etaMap[g.muscle]),
                    statusDotColor: _dotColor(hx, deloadByMuscle[g.muscle]),
                  ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                Text('Error: $e', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  String _formatEta(double? hours) {
    if (hours == null) return 'Recovered';
    if (hours >= MuscleRecoveryV3.maxEtaHorizonHours) return '10d+';
    if (hours < 48) return '~${hours.round()}h';
    return '~${(hours / 24).round()}d';
  }

  Color? _dotColor(HxColors hx, DeloadUrgency? urgency) {
    return switch (urgency) {
      DeloadUrgency.recommended => hx.danger,
      DeloadUrgency.watch => hx.warning,
      _ => null,
    };
  }
}
