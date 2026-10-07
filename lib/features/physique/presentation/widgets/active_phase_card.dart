import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/sheets/roadmap_editor_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_type_pill.dart';

DietPhase _phaseOf(String name) => DietPhase.values.firstWhere(
  (p) => p.name == name,
  orElse: () => DietPhase.maintain,
);

/// The active phase from the persisted roadmap: position, time in phase, tempo
/// and exit criteria (PHYS-05). Offers the next phase and never forces it, and
/// never writes a calorie target (D-02).
class ActivePhaseCard extends ConsumerWidget {
  const ActivePhaseCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    final phasesAsync = ref.watch(physiqueRoadmapPhasesProvider(goalId));
    final phases = phasesAsync.asData?.value;
    final status = ref.watch(physiquePhaseStatusProvider(goalId));
    final hx = context.hx;

    Widget body;
    if (goal == null || phases == null || status == null) {
      body = phasesAsync.hasError
          ? PhysiqueLoadError(
              onRetry: () =>
                  ref.invalidate(physiqueRoadmapPhasesProvider(goalId)),
            )
          : const PhysiqueLoading();
    } else if (phases.isEmpty) {
      return const SizedBox.shrink();
    } else {
      final proposal = status.proposalPending;
      final active = goal.status == 'active';
      final shown = proposal ? phases.first : (status.current ?? phases.last);
      final position = proposal ? 1 : phases.indexOf(shown) + 1;
      body = _Body(
        goalId: goalId,
        phase: shown,
        position: position,
        status: status,
        proposal: proposal,
        active: active,
        hx: hx,
      );
    }
    return SizedBox(
      width: double.infinity,
      child: HxCard(accent: hx.domainNutrition, child: body),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.goalId,
    required this.phase,
    required this.position,
    required this.status,
    required this.proposal,
    required this.active,
    required this.hx,
  });

  final int goalId;
  final PhysiqueRoadmapPhaseData phase;
  final int position;
  final PhysiquePhaseStatus status;
  final bool proposal;
  final bool active;
  final HxColors hx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = _phaseOf(phase.phaseType);
    final eval = (proposal || phase != status.current)
        ? null
        : status.evaluation;
    final tempo = _tempo(type, phase.weeklyRateKg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(HxSpace.x2),
              decoration: BoxDecoration(
                color: hx.domainNutrition.withValues(alpha: 0.14),
                borderRadius: HxRadius.mdAll,
              ),
              child: Icon(
                PhaseTypeIcon.of(type),
                size: 24,
                color: hx.onSurface,
              ),
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: HxSpace.x2,
                children: [
                  Text(
                    type.label,
                    style: PhysiqueText.display(context, color: hx.onSurface),
                  ),
                  Text(
                    'Phase $position of ${status.total}',
                    style: PhysiqueText.label(context, color: hx.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (eval != null) ...[
          const SizedBox(height: HxSpace.x4),
          Text(
            'Week ${eval.weekInPhase} of ${eval.plannedWeeks}',
            style: PhysiqueText.bodyTabular(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x2),
          _WeekBar(
            value: ((eval.weekInPhase - 1) / eval.plannedWeeks).clamp(0.0, 1.0),
            hx: hx,
          ),
        ],
        if (tempo != null) ...[
          const SizedBox(height: HxSpace.x3),
          Text(
            tempo,
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
        if (proposal) ...[
          const SizedBox(height: HxSpace.x3),
          Text(
            'This roadmap is a proposal until you accept it.',
            style: PhysiqueText.body(context, color: hx.onSurface),
          ),
        ],
        if (eval != null) ..._exitRows(context, eval),
        if (eval != null &&
            active &&
            status.logMeasurementsHint &&
            eval.criteria.any((c) => c.kind == ExitCriterionKind.bodyFat))
          TextButton(
            onPressed: () => context.push(AppRoutes.measurements),
            child: const Text('Log measurements to refine this.'),
          ),
        if (active && !proposal && status.offerAdvance && status.next != null)
          _AdvancePrompt(goalId: goalId, next: status.next!, hx: hx),
        if (active) _Footer(goalId: goalId, phase: type, proposal: proposal),
      ],
    );
  }

  static String? _tempo(DietPhase type, double? rate) => switch (type) {
    DietPhase.maintain => 'Hold your weight steady',
    DietPhase.recomp => 'Weight stays flat while body composition shifts',
    _ =>
      rate == null
          ? null
          : 'About ${rate.abs().toStringAsFixed(1)} kg per week',
  };

  List<Widget> _exitRows(BuildContext context, ExitEvaluation eval) {
    if (eval.criteria.isEmpty) return const [];
    String text(ExitCriterionStatus c) => switch (c.kind) {
      ExitCriterionKind.weight => 'Reach ${c.target!.toStringAsFixed(1)} kg',
      ExitCriterionKind.bodyFat => 'Reach about ${c.target!.round()}% body fat',
      ExitCriterionKind.duration =>
        'Or finish the planned ${eval.plannedWeeks} weeks',
    };
    return [
      const SizedBox(height: HxSpace.x4),
      Text('Exit when', style: PhysiqueText.heading(context)),
      const SizedBox(height: HxSpace.x2),
      for (final c in eval.criteria)
        Padding(
          padding: const EdgeInsets.only(bottom: HxSpace.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                c.met
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: c.met ? hx.success : hx.secondary,
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: Text(
                  text(c),
                  style: PhysiqueText.body(context, color: hx.onSurface),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.value, required this.hx});

  final double value;
  final HxColors hx;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: HxRadius.pillAll,
        child: SizedBox(
          height: 8,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: hx.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(hx.domainNutrition),
          ),
        ),
      ),
    );
  }
}

class _AdvancePrompt extends ConsumerWidget {
  const _AdvancePrompt({
    required this.goalId,
    required this.next,
    required this.hx,
  });

  final int goalId;
  final PhysiqueRoadmapPhaseData next;
  final HxColors hx;

  Future<void> _advance(BuildContext context, WidgetRef ref) async {
    final notices = AppNotice.of(context);
    final router = GoRouter.of(context);
    final target = ref
        .read(physiqueRoadmapEligibilityProvider(goalId))
        .coerce(_phaseOf(next.phaseType));
    final label = _phaseOf(next.phaseType).label;
    final moved = await ref
        .read(physiqueRoadmapRepositoryProvider)
        .advancePhase(goalId);
    if (!moved) return;
    Haptics.light();
    notices.show(
      'Moved to $label. Review your nutrition targets.',
      actionLabel: 'Set targets',
      onAction: () => router.push(AppRoutes.nutritionTargets, extra: target),
    );
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    final notices = AppNotice.of(context);
    await ref.read(physiqueRoadmapRepositoryProvider).postponeAdvance(goalId);
    notices.show("We'll ask again in a week.", kind: AppNoticeKind.info);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _phaseOf(next.phaseType).label;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: HxSpace.x4),
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: BoxDecoration(
        color: hx.domainNutrition.withValues(alpha: 0.14),
        borderRadius: HxRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready for the next phase?',
            style: PhysiqueText.heading(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            "You've met this phase's goal. $label is next. Nothing changes "
            'until you set new targets.',
            style: PhysiqueText.body(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x3),
          Wrap(
            spacing: HxSpace.x2,
            runSpacing: HxSpace.x2,
            children: [
              FilledButton(
                onPressed: () => _advance(context, ref),
                child: Text('Move to $label'),
              ),
              TextButton(
                onPressed: () => _postpone(context, ref),
                child: const Text('Not yet'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.goalId,
    required this.phase,
    required this.proposal,
  });

  final int goalId;
  final DietPhase phase;
  final bool proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: HxSpace.x2),
      child: Wrap(
        spacing: HxSpace.x2,
        children: [
          TextButton(
            onPressed: () => RoadmapEditorSheet.show(context, goalId: goalId),
            child: const Text('Edit roadmap'),
          ),
          if (!proposal)
            TextButton.icon(
              iconAlignment: IconAlignment.end,
              onPressed: () => context.push(
                AppRoutes.nutritionTargets,
                extra: ref
                    .read(physiqueRoadmapEligibilityProvider(goalId))
                    .coerce(phase),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Review nutrition targets'),
            ),
        ],
      ),
    );
  }
}
