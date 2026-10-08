import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';

DietPhase _phaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

/// The roadmap of [goalId] on the calendar, with the weight each phase starts
/// and ends at. Null until the goal and its phases have loaded, or when there
/// are no phases. Derived only; nothing is written.
final physiqueRoadmapScheduleProvider = Provider.family<RoadmapSchedule?, int>((
  ref,
  goalId,
) {
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  final rows = ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData?.value;
  if (goal == null || rows == null || rows.isEmpty) return null;
  final logs = ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
  final now = ref.watch(clockProvider).now();
  final proposal = goal.roadmapAcceptedAt == null;
  return RoadmapScheduleCalculator.build(
    phases: [
      for (final r in rows)
        SchedulePhaseInput(
          phase: _phaseOf(r.phaseType),
          plannedWeeks: r.plannedWeeks,
          targetWeightKg: r.targetWeightKg,
          targetBfPercent: r.targetBfPercent,
          status: proposal ? 'upcoming' : r.status,
          startedAt: r.startedAt,
          completedAt: r.completedAt,
        ),
    ],
    // A proposal has not started: it would begin today.
    anchor: proposal ? now : goal.startedAt,
    now: now,
    startWeightKg: goal.startWeightKg ?? (logs.isEmpty ? null : logs.first.kg),
  );
});
