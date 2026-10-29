import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_schedule_provider.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/roadmap_format.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';

/// Vertical timeline of every roadmap phase (never horizontal, so 200% text
/// and six or more phases cannot truncate). Each phase names the weight it
/// starts and ends at, its dates and its pace, so the whole plan reads as a
/// series of target weights.
class RoadmapTimelineCard extends ConsumerWidget {
  const RoadmapTimelineCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    final async = ref.watch(physiqueRoadmapPhasesProvider(goalId));
    final phases = async.asData?.value;
    final schedule = ref.watch(physiqueRoadmapScheduleProvider(goalId));
    final weightFormat = ref.watch(weightFormatProvider);
    final proposal = goal != null && goal.roadmapAcceptedAt == null;
    final hx = context.hx;

    if (phases == null) {
      return async.hasError
          ? PhysiqueLoadError(
              onRetry: () =>
                  ref.invalidate(physiqueRoadmapPhasesProvider(goalId)),
            )
          : const PhysiqueLoading();
    }
    if (phases.isEmpty) return const SizedBox.shrink();
    final total = phases.fold(0, (sum, p) => sum + p.plannedWeeks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhysiqueSectionTitle(
          'Phases',
          trailing: Text(
            '$total weeks total',
            style: TextStyle(
              color: hx.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (schedule != null) ...[
          const SizedBox(height: HxSpace.x1),
          _Summary(
            schedule: schedule,
            weightFormat: weightFormat,
            estimatedMonths: goal?.estimatedMonths,
          ),
        ],
        const SizedBox(height: HxSpace.x3),
        for (var i = 0; i < phases.length; i++)
          _TimelineRow(
            phase: phases[i],
            scheduled: schedule != null && i < schedule.phases.length
                ? schedule.phases[i]
                : null,
            weightFormat: weightFormat,
            index: i,
            last: i == phases.length - 1,
            proposal: proposal,
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.schedule,
    required this.weightFormat,
    required this.estimatedMonths,
  });

  final RoadmapSchedule schedule;
  final WeightFormat weightFormat;

  /// How long the analysis said the goal takes; null when unknown.
  final int? estimatedMonths;

  /// True when the roadmap stops well short of that, as the older roadmaps
  /// did (one short phase for a year-long goal).
  bool get _coversLess {
    final months = estimatedMonths;
    if (months == null) return false;
    return schedule.totalWeeks <
        months * PhysiqueTuning.weeksPerMonth - _coverSlackWeeks;
  }

  static const _coverSlackWeeks = 4;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final dream = schedule.dreamWeightKg;
    final months = schedule.totalMonths;
    final span =
        '${schedule.totalWeeks} weeks'
        '${months >= 2 ? ' · about $months months' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          span,
          style: PhysiqueText.label(context, color: hx.onSurfaceVariant),
        ),
        if (dream != null)
          Text(
            'Dream weight ${weightFormat.format(dream)}',
            key: const Key('timeline-dream-weight'),
            style: PhysiqueText.bodyStrong(context, color: hx.onSurface),
          ),
        if (_coversLess)
          Padding(
            padding: const EdgeInsets.only(top: HxSpace.x1),
            child: Text(
              'This roadmap covers ${schedule.totalMonths} of '
              '$estimatedMonths months. Use Update roadmap below to plan the '
              'rest.',
              key: const Key('timeline-covers-less'),
              style: PhysiqueText.label(context, color: hx.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.phase,
    required this.scheduled,
    required this.weightFormat,
    required this.index,
    required this.last,
    required this.proposal,
  });

  final PhysiqueRoadmapPhaseData phase;
  final ScheduledPhase? scheduled;
  final WeightFormat weightFormat;
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
    final type = physiquePhaseOf(phase.phaseType);
    final label = type.label;
    final color = physiquePhaseColor(type, hx);
    final current = state == 'current';
    final weeks = '${phase.plannedWeeks} weeks';
    final s = scheduled;
    final range = s == null ? '' : roadmapWeightRange(s, weightFormat);
    final pace = s == null ? '' : roadmapPace(s, weightFormat);
    final bf = phase.targetBfPercent;
    final small = TextStyle(
      color: hx.secondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      container: true,
      label:
          '$label, $weeks, ${range.isEmpty ? '' : '$range, '}'
          '${s == null ? '' : '${roadmapDateRange(s)}, '}$status',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 22,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    _Node(state: state, index: index, color: color),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 4),
                          color: hx.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(bottom: last ? 0 : 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: current
                        ? color.withValues(alpha: 0.07)
                        : hx.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: current
                          ? color.withValues(alpha: 0.35)
                          : hx.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(
                                color: hx.tertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            weeks,
                            style: TextStyle(
                              color: hx.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (range.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: HxSpace.x2,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            Text(
                              range,
                              key: Key('timeline-weights-$index'),
                              style: physiqueDisplay(
                                20,
                                weight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (pace.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  pace,
                                  style: small.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 3),
                      if (s != null)
                        Text(
                          roadmapDateRange(s),
                          key: Key('timeline-dates-$index'),
                          style: small,
                        ),
                      if (bf != null)
                        Text(
                          'Target ${bf.toStringAsFixed(bf.truncateToDouble() == bf ? 0 : 1)}% body fat',
                          style: small,
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
  const _Node({required this.state, required this.index, required this.color});

  final String state;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      key: Key(
        'timeline-node-${switch (state) {
          'done' => 'done',
          'current' => 'current',
          _ => 'upcoming',
        }}-$index',
      ),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == 'current'
            ? color
            : state == 'done'
            ? color.withValues(alpha: 0.35)
            : hx.background,
        border: Border.all(color: color, width: 2.5),
      ),
      child: state == 'done'
          ? Icon(Icons.check_rounded, size: 12, color: hx.onSurface)
          : null,
    );
  }
}
