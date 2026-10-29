import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';

/// The roadmap in one strip on the progress screen: the current phase, how far
/// into it you are, what comes next, and the way to the full roadmap.
class PhaseStripCard extends ConsumerWidget {
  const PhaseStripCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final phases = ref
        .watch(physiqueRoadmapPhasesProvider(goalId))
        .asData
        ?.value;
    final status = ref.watch(physiquePhaseStatusProvider(goalId));
    if (phases == null || phases.isEmpty || status == null) {
      return const SizedBox.shrink();
    }
    final proposal = status.proposalPending;
    final shown = proposal ? phases.first : (status.current ?? phases.last);
    final type = physiquePhaseOf(shown.phaseType);
    final color = physiquePhaseColor(type, hx);
    final position = phases.indexOf(shown) + 1;
    final eval = proposal ? null : status.evaluation;
    final next = proposal
        ? (phases.length > 1 ? phases[1] : null)
        : status.next;
    final weeksLeft = eval == null
        ? shown.plannedWeeks
        : (eval.plannedWeeks - eval.weekInPhase + 1).clamp(0, 999);
    final nextLine = status.offerAdvance && !proposal
        ? 'Ready for the next phase — open the roadmap'
        : next == null
        ? 'Last phase of the roadmap'
        : 'Next: ${physiquePhaseOf(next.phaseType).label.toLowerCase()} in '
              '$weeksLeft ${weeksLeft == 1 ? 'week' : 'weeks'}';

    double fill(int i) {
      final p = phases[i];
      if (proposal) return 0;
      if (p.status == 'done') return 1;
      if (p == status.current && eval != null) {
        return ((eval.weekInPhase - 1) / eval.plannedWeeks).clamp(0.0, 1.0);
      }
      return 0;
    }

    void open() => context.push(AppPaths.dreamPhysiqueRoadmap(goalId: goalId));

    return Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.55],
            colors: [color.withValues(alpha: 0.12), hx.surfaceContainerLowest],
          ),
        ),
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PhysiqueEyebrow(
                        proposal
                            ? 'PROPOSED · ${type.label.toUpperCase()}'
                            : '${type.label.toUpperCase()} · PHASE $position OF ${phases.length}',
                        color: color,
                      ),
                    ),
                    if (eval != null)
                      Flexible(
                        child: Text(
                          'Week ${eval.weekInPhase} / ${eval.plannedWeeks}',
                          style: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Icon(Icons.chevron_right_rounded, color: hx.secondary),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < phases.length; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        flex: phases[i].plannedWeeks.clamp(1, 999),
                        child: PhysiqueBar(
                          value: fill(i),
                          height: 8,
                          color: physiquePhaseColor(
                            physiquePhaseOf(phases[i].phaseType),
                            hx,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  proposal
                      ? 'This roadmap is a proposal until you accept it.'
                      : nextLine,
                  style: TextStyle(
                    color: hx.secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Color.lerp(color, hx.onSurface, 0.25),
                      backgroundColor: color.withValues(alpha: 0.10),
                      side: BorderSide(color: color.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: open,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text('View roadmap'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
