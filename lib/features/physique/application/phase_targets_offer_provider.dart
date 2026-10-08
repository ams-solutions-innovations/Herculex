import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Calories and macros worked out for the roadmap's running phase, offered to
/// the member. Nothing is written until they accept (house rule: the roadmap
/// never changes nutrition targets on its own).
class PhaseTargetsOffer {
  const PhaseTargetsOffer({
    required this.goalId,
    required this.phase,
    required this.pace,
    required this.targets,
    required this.currentPlan,
  });

  final int goalId;
  final DietPhase phase;
  final DietPaceOption pace;
  final PhaseTargets targets;

  /// The phase the calories are set for now; null when never set.
  final DietPhase? currentPlan;
}

/// The preset closest to the roadmap phase's own weekly rate. Phases with a
/// single preset (maintain, recomp) get that one.
DietPaceOption nearestPace(DietPhase phase, double? weeklyRateKg) {
  final options = DietPhaseCalculator.paceOptionsFor(phase);
  if (weeklyRateKg == null) return options[options.length > 1 ? 1 : 0];
  var best = options.first;
  for (final o in options) {
    final better =
        (o.weeklyKg - weeklyRateKg).abs() <
        (best.weeklyKg - weeklyRateKg).abs();
    if (better) best = o;
  }
  return best;
}

DietPhase _phaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

/// Offers for (goal, phase) pairs the member waved away, as `"goalId:phase"`.
class PhaseTargetsOfferDismissals extends Notifier<Set<String>> {
  static const _key = 'physique_targets_offer_dismissed';

  static String keyFor(int goalId, DietPhase phase) => '$goalId:${phase.name}';

  @override
  Set<String> build() =>
      (ref.watch(sharedPreferencesProvider).getStringList(_key) ?? const [])
          .toSet();

  Future<void> dismiss(int goalId, DietPhase phase) async {
    final next = {...state, keyFor(goalId, phase)};
    await ref.read(sharedPreferencesProvider).setStringList(_key, [...next]);
    state = next;
  }
}

final phaseTargetsOfferDismissalsProvider =
    NotifierProvider<PhaseTargetsOfferDismissals, Set<String>>(
      PhaseTargetsOfferDismissals.new,
    );

/// An offer when the roadmap is running and the calorie plan is not for its
/// current phase (or was never set); null otherwise. Derived only.
final phaseTargetsOfferProvider = Provider.family<PhaseTargetsOffer?, int>((
  ref,
  goalId,
) {
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  if (goal == null ||
      goal.status != 'active' ||
      goal.roadmapAcceptedAt == null) {
    return null;
  }
  final phases = ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData?.value;
  final current = phases?.where((p) => p.status == 'current').firstOrNull;
  if (current == null) return null;

  final eligibility = ref.watch(physiqueRoadmapEligibilityProvider(goalId));
  final phase = eligibility.coerce(_phaseOf(current.phaseType));

  final plan = ref.watch(activeDietPlanProvider);
  if (plan.isSet && plan.phase == phase) return null;
  final dismissed = ref.watch(phaseTargetsOfferDismissalsProvider);
  if (dismissed.contains(PhaseTargetsOfferDismissals.keyFor(goalId, phase))) {
    return null;
  }

  final weightKg = ref.watch(profileProvider).asData?.value?.weightKg;
  final minimums = ref.watch(minimumTargetsProvider);
  // The roadmap's rate only fits the phase it was planned for; a phase the
  // guardrails swapped in gets the standard pace.
  final pace = nearestPace(
    phase,
    phase.name == current.phaseType ? current.weeklyRateKg : null,
  );
  final targets = DietPhaseCalculator.apply(
    phase: phase,
    eligibility: eligibility,
    baselineKcal:
        ref.watch(maintenanceKcalProvider) ??
        PhysiqueTuning.defaultMaintenanceKcal,
    bodyweightKg: weightKg,
    calorieDeltaOverride: pace.kcalDelta,
    minProteinG: minimums.resolvedMinProteinG(weightKg),
    minCaloriesKcal: minimums.effectiveMinCaloriesKcal,
  );
  return PhaseTargetsOffer(
    goalId: goalId,
    phase: phase,
    pace: pace,
    targets: targets,
    currentPlan: plan.isSet ? plan.phase : null,
  );
});
