import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/components/hx_top_tabs.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/past_goals_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/check_in_card.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_strip_card.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';
import 'package:herculex/features/physique/presentation/widgets/progress_hero_card.dart';
import 'package:herculex/features/physique/presentation/widgets/progress_metrics_grid.dart';
import 'package:herculex/features/physique/presentation/widgets/restriction_notice.dart';
import 'package:herculex/features/physique/presentation/widgets/strength_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/training_level_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/weight_chart_card.dart';
import 'package:herculex/features/programs/presentation/widgets/block_adjustment_card.dart';

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
    final archivedCount =
        ref.watch(archivedPhysiqueGoalsProvider).asData?.value.length ?? 0;
    final range = ref.watch(physiqueEffectiveRangeProvider(id));
    final hx = context.hx;

    const gap = SizedBox(height: 10);
    const section = SizedBox(height: 26);
    return HxScreenShell(
      title: 'Physique progress',
      titleIcon: Icons.auto_awesome,
      actions: [
        if (goal != null && goal.status == 'active')
          IconButton(
            tooltip: 'Roadmap',
            onPressed: () =>
                context.push(AppPaths.dreamPhysiqueRoadmap(goalId: id)),
            icon: const Icon(Icons.route_rounded),
          ),
      ],
      children: [
        const SizedBox(height: HxSpace.x8),
        ProgressHeroCard(goalId: id),
        if (!archived) ...[
          gap,
          RestrictionNoticeList(
            eligibility: ref.watch(physiqueRoadmapEligibilityProvider(id)),
            onAddAge: () => context.push(AppRoutes.profile),
            onLogMeasurements: () => context.push(AppRoutes.measurements),
          ),
        ],
        gap,
        // The advance prompt lives on the roadmap screen, so the check-in
        // stays the primary action here.
        CheckInCard(goalId: id, advancePromptVisible: false),
        gap,
        ProgressMetricsGrid(goalId: id),
        gap,
        PhaseStripCard(goalId: id),
        // The training side of the goal: rebuild the block when life or
        // recovery no longer matches it.
        if (!archived) ...[gap, const BlockAdjustmentCard()],
        section,
        PhysiqueSectionTitle(
          'Weight',
          trailing: SizedBox(
            width: 200,
            child: HxTopTabs(
              labels: [for (final r in ChartRange.values) r.label],
              index: ChartRange.values.indexOf(range),
              onChanged: (i) =>
                  ref.read(physiqueChartRangeProvider.notifier).state =
                      ChartRange.values[i],
            ),
          ),
        ),
        gap,
        WeightChartCard(goalId: id),
        section,
        StrengthChartCard(goalId: id),
        gap,
        TrainingLevelChartCard(goalId: id),
        if (!archived && archivedCount > 0) ...[
          gap,
          _PastGoalsRow(count: archivedCount),
        ],
        const SizedBox(height: 22),
        Text(
          'Body-fat and progress figures are estimates from your photos and '
          'weigh-ins, not measurements.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: hx.tertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
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
