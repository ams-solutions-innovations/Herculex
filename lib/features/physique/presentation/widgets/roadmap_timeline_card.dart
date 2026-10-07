import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';

/// Vertical timeline of every roadmap phase (never horizontal, so 200% text
/// and six or more phases cannot truncate).
class RoadmapTimelineCard extends ConsumerWidget {
  const RoadmapTimelineCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    final async = ref.watch(physiqueRoadmapPhasesProvider(goalId));
    final phases = async.asData?.value;
    final proposal = goal != null && goal.roadmapAcceptedAt == null;
    final hx = context.hx;

    Widget body;
    if (phases == null) {
      body = async.hasError
          ? PhysiqueLoadError(
              onRetry: () =>
                  ref.invalidate(physiqueRoadmapPhasesProvider(goalId)),
            )
          : const PhysiqueLoading();
    } else if (phases.isEmpty) {
      return const SizedBox.shrink();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roadmap',
            style: PhysiqueText.heading(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x4),
          for (var i = 0; i < phases.length; i++)
            _TimelineRow(
              phase: phases[i],
              index: i,
              last: i == phases.length - 1,
              proposal: proposal,
            ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: HxCard(child: body),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.phase,
    required this.index,
    required this.last,
    required this.proposal,
  });

  final PhysiqueRoadmapPhaseData phase;
  final int index;
  final bool last;
  final bool proposal;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final state = proposal ? 'upcoming' : phase.status;
    final status = switch (state) {
      'done' => 'Done',
      'current' => 'Current',
      _ => 'Up next',
    };
    final label = DietPhase.values
        .firstWhere(
          (p) => p.name == phase.phaseType,
          orElse: () => DietPhase.maintain,
        )
        .label;
    final weeks = '${phase.plannedWeeks} weeks';

    return Semantics(
      container: true,
      label: '$label, $weeks, $status',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 16,
                child: Column(
                  children: [
                    _Node(state: state, index: index),
                    if (!last)
                      Expanded(
                        child: Container(width: 2, color: hx.outlineVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : HxSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: PhysiqueText.bodyStrong(
                          context,
                          color: hx.onSurface,
                        ),
                      ),
                      Wrap(
                        spacing: HxSpace.x3,
                        children: [
                          Text(
                            weeks,
                            style: PhysiqueText.labelTabular(
                              context,
                              color: hx.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            status,
                            style: PhysiqueText.labelStrong(
                              context,
                              color: hx.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.state, required this.index});

  final String state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return switch (state) {
      'done' => Container(
        key: Key('timeline-node-done-$index'),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: hx.domainNutrition,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, size: 12, color: hx.onPrimary),
      ),
      'current' => Container(
        key: Key('timeline-node-current-$index'),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: hx.primary, width: 2),
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: hx.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      _ => Container(
        key: Key('timeline-node-upcoming-$index'),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: hx.outlineVariant, width: 2),
        ),
      ),
    };
  }
}
