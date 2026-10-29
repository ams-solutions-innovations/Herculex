import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';

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
    var accent = hx.warning;
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
      accent = physiquePhaseColor(_phaseOf(shown.phaseType), hx);
      body = _Body(
        goalId: goalId,
        phase: shown,
        position: position,
        status: status,
        proposal: proposal,
        active: active,
        accent: accent,
        hx: hx,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.55],
          colors: [accent.withValues(alpha: 0.16), hx.surfaceContainerLowest],
        ),
      ),
      child: body,
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
    required this.accent,
    required this.hx,
  });

  final int goalId;
  final PhysiqueRoadmapPhaseData phase;
  final int position;
  final PhysiquePhaseStatus status;
  final bool proposal;
  final bool active;
  final Color accent;
  final HxColors hx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = _phaseOf(phase.phaseType);
    final eval = (proposal || phase != status.current)
        ? null
        : status.evaluation;
    final wf = ref.watch(weightFormatProvider);
    final weights =
        ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
    final latestKg = weights.isEmpty ? null : weights.last.kg;
    final checkIns =
        ref.watch(physiqueCheckInsProvider(goalId)).asData?.value ?? const [];
    final verdict = checkIns.isEmpty
        ? null
        : CheckInVerdict.fromWire(checkIns.first.verdict);
    final (trend, trendColor) = switch (verdict) {
      CheckInVerdict.onTrack => ('On track', hx.success),
      CheckInVerdict.offTrack => ('Off track', hx.warning),
      CheckInVerdict.inconclusive => ('Unclear', hx.secondary),
      null => ('—', hx.secondary),
    };
    final target = phase.targetWeightKg != null
        ? wf.format(phase.targetWeightKg!)
        : phase.targetBfPercent != null
        ? '~${phase.targetBfPercent!.round()}% BF'
        : '—';
    // Dark ink on the bright phase pill, as in the design ("NOW · CUT").
    final ink = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? hx.onPrimary
        : hx.background;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: HxRadius.pillAll,
              ),
              child: Text(
                '${proposal ? 'PROPOSED' : 'NOW'} · ${type.label.toUpperCase()}',
                style: TextStyle(
                  color: ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Phase $position of ${status.total}',
                style: TextStyle(
                  color: hx.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (eval != null) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Week ${eval.weekInPhase} of ${eval.plannedWeeks}',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                text: 'Week ${eval.weekInPhase}',
                style: physiqueDisplay(
                  52,
                  weight: FontWeight.w600,
                  letterSpacing: -2,
                  height: 1,
                ),
                children: [
                  TextSpan(
                    text: '  / ${eval.plannedWeeks}',
                    style: physiqueDisplay(
                      20,
                      weight: FontWeight.w600,
                      color: hx.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _WeekTicks(
            week: eval.weekInPhase,
            planned: eval.plannedWeeks,
            color: accent,
          ),
        ],
        if (proposal) ...[
          const SizedBox(height: 12),
          Text(
            'This roadmap is a proposal until you accept it.',
            style: PhysiqueText.body(context, color: hx.onSurface),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PhysiqueMiniTile(
                label: 'PACE',
                value: _pace(type, phase.weeklyRateKg, wf),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PhysiqueMiniTile(label: 'TARGET', value: target),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PhysiqueMiniTile(
                label: 'TREND',
                value: trend,
                valueColor: trendColor,
              ),
            ),
          ],
        ),
        if (eval != null)
          ..._exitRows(
            context,
            eval,
            latestKg: latestKg,
            bf: status.bfReading,
            wf: wf,
          ),
        if (eval != null &&
            active &&
            status.logMeasurementsHint &&
            eval.criteria.any((c) => c.kind == ExitCriterionKind.bodyFat))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.measurements),
              child: const Text('Log measurements to refine this.'),
            ),
          ),
        if (active && !proposal && status.offerAdvance && status.next != null)
          _AdvancePrompt(goalId: goalId, next: status.next!, hx: hx),
        if (active && !proposal) _Footer(goalId: goalId, phase: type),
      ],
    );
  }

  /// "−0.4 kg/wk", or what a holding phase does instead.
  static String _pace(DietPhase type, double? rate, WeightFormat wf) =>
      switch (type) {
        DietPhase.maintain => 'Hold steady',
        DietPhase.recomp => 'Hold weight',
        _ =>
          rate == null || rate == 0
              ? '—'
              : '${type == DietPhase.cut ? '−' : '+'}'
                    '${wf.formatValue(rate.abs())} ${wf.suffix}/wk',
      };

  List<Widget> _exitRows(
    BuildContext context,
    ExitEvaluation eval, {
    required double? latestKg,
    required PhysiqueBfReading bf,
    required WeightFormat wf,
  }) {
    if (eval.criteria.isEmpty) return const [];
    String text(ExitCriterionStatus c) => switch (c.kind) {
      ExitCriterionKind.weight => 'Reach ${c.target!.toStringAsFixed(1)} kg',
      ExitCriterionKind.bodyFat => 'Reach about ${c.target!.round()}% body fat',
      ExitCriterionKind.duration =>
        'Or finish the planned ${eval.plannedWeeks} weeks',
    };
    String? now(ExitCriterionStatus c) => switch (c.kind) {
      ExitCriterionKind.weight =>
        latestKg == null ? null : 'now ${wf.formatValue(latestKg)}',
      ExitCriterionKind.bodyFat =>
        bf.percent == null
            ? null
            : 'now ${bf.source == PhysiqueBfSource.estimate ? '~' : ''}'
                  '${bf.percent!.round()}%',
      ExitCriterionKind.duration => () {
        final left = eval.plannedWeeks - eval.weekInPhase + 1;
        return left <= 0 ? 'done' : '$left left';
      }(),
    };
    IconData icon(ExitCriterionKind k) => switch (k) {
      ExitCriterionKind.weight => Icons.monitor_weight_outlined,
      ExitCriterionKind.bodyFat => Icons.water_drop_outlined,
      ExitCriterionKind.duration => Icons.event_outlined,
    };
    return [
      const SizedBox(height: 14),
      const PhysiqueEyebrow('EXIT WHEN'),
      const SizedBox(height: 8),
      for (final c in eval.criteria)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                c.met ? Icons.check_circle_rounded : icon(c.kind),
                size: 18,
                color: c.met
                    ? hx.success
                    : c.kind == ExitCriterionKind.duration
                    ? hx.secondary
                    : accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text(c),
                  style: TextStyle(
                    color: hx.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (now(c) != null)
                Text(
                  now(c)!,
                  style: TextStyle(
                    color: c.kind == ExitCriterionKind.duration
                        ? hx.secondary
                        : accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}

/// One tick per planned week: done, this week, still ahead.
class _WeekTicks extends StatelessWidget {
  const _WeekTicks({
    required this.week,
    required this.planned,
    required this.color,
  });

  final int week;
  final int planned;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    // Past a few dozen weeks ticks blur together; a bar reads better.
    if (planned > 30) {
      return ExcludeSemantics(
        child: PhysiqueBar(
          value: ((week - 1) / planned).clamp(0.0, 1.0),
          color: color,
          height: 8,
        ),
      );
    }
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < planned; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: i < week - 1
                      ? color
                      : i == week - 1
                      ? color.withValues(alpha: 0.45)
                      : hx.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
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

/// The nutrition side of the phase. Editing the roadmap itself lives on the
/// roadmap screen's own action row.
class _Footer extends ConsumerWidget {
  const _Footer({required this.goalId, required this.phase});

  final int goalId;
  final DietPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
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
    );
  }
}
