import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// The goal a roadmap phase stands for. A lean bulk is still a gaining phase;
/// the finer calorie difference comes from the phase offer, not from here.
FitnessGoal fitnessGoalForPhase(DietPhase phase) => switch (phase) {
  DietPhase.cut => FitnessGoal.weightLoss,
  DietPhase.bulk || DietPhase.maingain => FitnessGoal.muscleGain,
  DietPhase.maintain || DietPhase.recomp => FitnessGoal.maintenance,
};

/// The goal the app works towards right now.
///
/// While an accepted roadmap has a running phase it is what that phase stands
/// for (after the guardrails, so a member under 18 never reads as cutting).
/// Otherwise it is the goal chosen in onboarding. The stored goal is never
/// touched, so it is still there when the roadmap ends.
///
/// Baseline calories, Hercul and workout progression read this. Whatever feeds
/// the roadmap generator (`prefersWeightLoss`) keeps reading the stored goal,
/// or the roadmap would end up reading its own output.
final effectiveFitnessGoalProvider = Provider<FitnessGoal?>((ref) {
  final stored = ref.watch(profileProvider).asData?.value?.goal;

  final goal = ref.watch(activePhysiqueGoalProvider).asData?.value;
  if (goal == null || goal.roadmapAcceptedAt == null) return stored;
  final phases = ref
      .watch(physiqueRoadmapPhasesProvider(goal.id))
      .asData
      ?.value;
  final current = phases?.where((p) => p.status == 'current').firstOrNull;
  if (current == null) return stored;

  final eligibility = ref.watch(physiqueRoadmapEligibilityProvider(goal.id));
  final phase = eligibility.coerce(
    DietPhase.values.asNameMap()[current.phaseType] ?? DietPhase.maintain,
  );
  return fitnessGoalForPhase(phase);
});
