import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/components/hx_top_tabs.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/phase_targets_offer_provider.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/past_goals_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/active_phase_card.dart';
import 'package:herculex/features/physique/presentation/widgets/check_in_card.dart';
import 'package:herculex/features/physique/presentation/widgets/goal_header_card.dart';
import 'package:herculex/features/physique/presentation/widgets/goal_progress_card.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_targets_offer_card.dart';
import 'package:herculex/features/physique/presentation/widgets/restriction_notice.dart';
import 'package:herculex/features/physique/presentation/widgets/roadmap_timeline_card.dart';
import 'package:herculex/features/physique/presentation/widgets/strength_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/training_level_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/weight_chart_card.dart';

/// S1: the Physique progress screen. [goalId] null means the active goal.
class PhysiqueProgressView extends ConsumerStatefulWidget {
  const PhysiqueProgressView({super.key, this.goalId});

  final int? goalId;

  @override
  ConsumerState<PhysiqueProgressView> createState() =>
      _PhysiqueProgressViewState();
}

class _PhysiqueProgressViewState extends ConsumerState<PhysiqueProgressView> {
  bool _resumeScheduled = false;

  /// Opens the check-in sheet once for a camera capture that outlived the
  /// activity, then clears it so a rebuild cannot reopen the sheet.
  void _maybeResume(PhysiqueGoalData goal) {
    final resumed = ref.read(physiqueResumedCaptureProvider);
    if (_resumeScheduled || resumed == null || resumed.goalId != goal.id) {
      return;
    }
    if (goal.status != 'active') return;
    _resumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(physiqueResumedCaptureProvider);
      if (current == null) return;
      ref.read(physiqueResumedCaptureProvider.notifier).state = null;
      CheckInSheet.show(context, goal: goal, resumed: current);
    });
  }

  @override
  Widget build(BuildContext context) {
    final requested = widget.goalId;
    final activeAsync = requested == null
        ? ref.watch(activePhysiqueGoalProvider)
        : null;
    final id = requested ?? activeAsync?.asData?.value?.id;

    if (id == null) {
      if (activeAsync != null && activeAsync.isLoading) {
        return const HxScreenShell(
          title: 'Physique progress',
          children: [
            SizedBox(height: HxSpace.x8),
            PhysiqueLoading(),
          ],
        );
      }
      if (activeAsync != null && activeAsync.hasError) {
        return HxScreenShell(
          title: 'Physique progress',
          children: [
            const SizedBox(height: HxSpace.x8),
            PhysiqueLoadError(
              onRetry: () => ref.invalidate(activePhysiqueGoalProvider),
            ),
          ],
        );
      }
      return const _NoGoalState();
    }

    final goal = ref.watch(physiqueGoalProvider(id)).asData?.value;
    if (goal != null) _maybeResume(goal);
    final archived = goal != null && goal.status == 'archived';
    final offerAdvance =
        ref.watch(physiquePhaseStatusProvider(id))?.offerAdvance ?? false;
    final archivedCount =
        ref.watch(archivedPhysiqueGoalsProvider).asData?.value.length ?? 0;
    final range = ref.watch(physiqueEffectiveRangeProvider(id));
    final hasTargetsOffer =
        !archived && ref.watch(phaseTargetsOfferProvider(id)) != null;

    const gap = SizedBox(height: HxSpace.x4);
    return HxScreenShell(
      title: 'Physique progress',
      children: [
        const SizedBox(height: HxSpace.x8),
        GoalHeaderCard(goalId: id),
        gap,
        GoalProgressCard(goalId: id),
        if (!archived) ...[
          gap,
          RestrictionNoticeList(
            eligibility: ref.watch(physiqueRoadmapEligibilityProvider(id)),
            onAddAge: () => context.push(AppRoutes.profile),
            onLogMeasurements: () => context.push(AppRoutes.measurements),
          ),
        ],
        gap,
        ActivePhaseCard(goalId: id),
        if (hasTargetsOffer) ...[gap, PhaseTargetsOfferCard(goalId: id)],
        gap,
        RoadmapTimelineCard(goalId: id),
        gap,
        CheckInCard(goalId: id, advancePromptVisible: offerAdvance),
        gap,
        HxTopTabs(
          labels: [for (final r in ChartRange.values) r.label],
          index: ChartRange.values.indexOf(range),
          onChanged: (i) =>
              ref.read(physiqueChartRangeProvider.notifier).state =
                  ChartRange.values[i],
        ),
        gap,
        WeightChartCard(goalId: id),
        gap,
        StrengthChartCard(goalId: id),
        gap,
        TrainingLevelChartCard(goalId: id),
        if (!archived && archivedCount > 0) ...[
          gap,
          _PastGoalsRow(count: archivedCount),
        ],
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }
}

class _PastGoalsRow extends StatelessWidget {
  const _PastGoalsRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      onTap: () => PastGoalsSheet.show(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Past goals · $count',
              style: PhysiqueText.heading(context, color: hx.onSurface),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: hx.secondary),
        ],
      ),
    );
  }
}

class _NoGoalState extends StatelessWidget {
  const _NoGoalState();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxScreenShell(
      title: 'Physique progress',
      children: [
        const SizedBox(height: HxSpace.x8),
        Column(
          children: [
            Text(
              'No Dream Physique goal yet',
              textAlign: TextAlign.center,
              style: PhysiqueText.heading(context, color: hx.onSurface),
            ),
            const SizedBox(height: HxSpace.x2),
            Text(
              'Pick a target physique and Herculex AI will build a phased '
              'plan you can edit.',
              textAlign: TextAlign.center,
              style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
            ),
            const SizedBox(height: HxSpace.x6),
            FilledButton(
              onPressed: () => context.push(AppRoutes.dreamPhysique),
              child: const Text('Create my goal'),
            ),
          ],
        ),
      ],
    );
  }
}
