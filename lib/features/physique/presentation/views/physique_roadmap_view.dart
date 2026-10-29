import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/phase_targets_offer_provider.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_schedule_provider.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/roadmap_editor_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/active_phase_card.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_targets_offer_card.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';
import 'package:herculex/features/physique/presentation/widgets/roadmap_timeline_card.dart';
import 'package:herculex/features/physique/presentation/widgets/roadmap_weight_plan_chart.dart';
import 'package:intl/intl.dart';

/// The Dream Physique roadmap: the goal, how far along the whole plan you
/// are, the weight plan, the phase you are in and every phase after it.
/// [goalId] null means the active goal.
class PhysiqueRoadmapView extends ConsumerWidget {
  const PhysiqueRoadmapView({super.key, this.goalId});

  final int? goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = goalId == null
        ? ref.watch(activePhysiqueGoalProvider)
        : null;
    final id = goalId ?? activeAsync?.asData?.value?.id;
    if (id == null) {
      return HxScreenShell(
        title: 'Roadmap',
        titleIcon: Icons.route_rounded,
        children: [
          const SizedBox(height: HxSpace.x8),
          if (activeAsync != null && activeAsync.hasError)
            PhysiqueLoadError(
              onRetry: () => ref.invalidate(activePhysiqueGoalProvider),
            )
          else if (activeAsync != null && activeAsync.isLoading)
            const PhysiqueLoading()
          else
            const Text('No Dream Physique goal yet.'),
        ],
      );
    }

    final hx = context.hx;
    final goal = ref.watch(physiqueGoalProvider(id)).asData?.value;
    final active = goal?.status == 'active';
    final hasOffer = active && ref.watch(phaseTargetsOfferProvider(id)) != null;
    final next = ref.watch(physiqueNextCheckInProvider(id));
    final nextLine = next == null
        ? 'A check-in is open today.'
        : 'Next check-in ${DateFormat('EEEE').format(next)}.';

    return HxScreenShell(
      title: 'Roadmap',
      titleIcon: Icons.route_rounded,
      children: [
        _Header(goalId: id),
        const SizedBox(height: 16),
        _OverallProgress(goalId: id),
        const SizedBox(height: 16),
        RoadmapWeightPlanChart(goalId: id),
        const SizedBox(height: 12),
        ActivePhaseCard(goalId: id),
        if (hasOffer) ...[
          const SizedBox(height: 12),
          PhaseTargetsOfferCard(goalId: id),
        ],
        const SizedBox(height: 28),
        RoadmapTimelineCard(goalId: id),
        if (active && goal != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hx.onSurface,
                      side: BorderSide(color: hx.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: () =>
                        RoadmapEditorSheet.show(context, goalId: id),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit roadmap'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: () => CheckInSheet.show(context, goal: goal),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Check in'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$nextLine Phases adjust from your weigh-ins and photos — '
            'nothing changes until you confirm.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.tertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

/// Goal photo, the roadmap's name and the end state in one line.
class _Header extends ConsumerWidget {
  const _Header({required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    if (goal == null) return const PhysiqueLoading();
    final phases =
        ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData?.value ??
        const [];
    final schedule = ref.watch(physiqueRoadmapScheduleProvider(goalId));
    final wf = ref.watch(weightFormatProvider);
    final uuid = goal.syncUuid;
    final dream = uuid == null
        ? null
        : ref.watch(physiqueDreamPhotoProvider(uuid)).asData?.value;

    final startKg = schedule?.startWeightKg ?? goal.startWeightKg;
    final dreamKg = schedule?.dreamWeightKg;
    final end = schedule?.endDate;
    final summary = [
      if (startKg != null && dreamKg != null)
        '${wf.formatValue(startKg)} → ${wf.format(dreamKg)}',
      if (goal.targetBfPercent != null)
        '~${goal.targetBfPercent!.round()}% body fat',
      if (end != null) DateFormat('MMM y').format(end),
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 64,
          height: 80,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: hx.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hx.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: dream == null
              ? Icon(Icons.flag_outlined, color: hx.tertiary)
              : Image.file(
                  dream,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhysiqueEyebrow(
                'YOUR ROADMAP · ${phases.length} '
                '${phases.length == 1 ? 'PHASE' : 'PHASES'}',
                color: hx.primaryText,
              ),
              const SizedBox(height: 2),
              Text(
                GoalDisplayCopy.title(goal.targetAestheticStyle),
                style: physiqueDisplay(24, letterSpacing: -0.5, height: 1.1),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: TextStyle(
                    color: hx.secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Week N of the whole roadmap as one bar.
class _OverallProgress extends ConsumerWidget {
  const _OverallProgress({required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final schedule = ref.watch(physiqueRoadmapScheduleProvider(goalId));
    final start = schedule?.startDate;
    if (schedule == null || start == null || schedule.totalWeeks == 0) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(clockProvider).now();
    final total = schedule.totalWeeks;
    final week = (now.difference(start).inDays ~/ 7 + 1).clamp(1, total);
    final fraction = (now.difference(start).inDays / (total * 7)).clamp(
      0.0,
      1.0,
    );
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: ColoredBox(
                color: hx.surfaceVariant,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [hx.primary, hx.primaryText],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Week $week of $total',
          style: TextStyle(
            color: hx.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
