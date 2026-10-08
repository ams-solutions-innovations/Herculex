import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/phase_targets_applier.dart';
import 'package:herculex/features/physique/application/phase_targets_offer_provider.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Offers the calories and macros for the roadmap's running phase when the
/// member's calorie plan is for another phase (or none). Applying is always a
/// tap: the roadmap never changes nutrition targets by itself.
class PhaseTargetsOfferCard extends ConsumerWidget {
  const PhaseTargetsOfferCard({super.key, required this.goalId});

  final int goalId;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    PhaseTargetsOffer offer,
  ) async {
    final notices = AppNotice.of(context);
    await ref
        .read(phaseTargetsApplierProvider)
        .apply(phase: offer.phase, pace: offer.pace, targets: offer.targets);
    notices.show(
      '${offer.phase.label} • ${offer.targets.kcal} kcal',
      title: 'Targets updated',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(phaseTargetsOfferProvider(goalId));
    if (offer == null) return const SizedBox.shrink();
    final hx = context.hx;
    final t = offer.targets;
    final current = offer.currentPlan;

    return SizedBox(
      width: double.infinity,
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Match your calories to this phase',
              style: PhysiqueText.heading(context, color: hx.onSurface),
            ),
            const SizedBox(height: HxSpace.x2),
            Text(
              '${current == null ? "You have not set calories for a phase yet." : "Your calories are set for ${current.label}."} '
              '${offer.phase.label} suggests ${t.kcal} kcal · '
              'P ${t.proteinG} / C ${t.carbsG} / F ${t.fatG} g.',
              key: const Key('phase-offer-text'),
              style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
            ),
            const SizedBox(height: HxSpace.x4),
            Wrap(
              spacing: HxSpace.x2,
              runSpacing: HxSpace.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  key: const Key('phase-offer-apply'),
                  onPressed: () => _apply(context, ref, offer),
                  child: const Text('Apply targets'),
                ),
                TextButton(
                  key: const Key('phase-offer-review'),
                  onPressed: () => context.push(
                    AppRoutes.nutritionTargets,
                    extra: offer.phase,
                  ),
                  child: const Text('Review first'),
                ),
                TextButton(
                  key: const Key('phase-offer-dismiss'),
                  onPressed: () => ref
                      .read(phaseTargetsOfferDismissalsProvider.notifier)
                      .dismiss(goalId, offer.phase),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
