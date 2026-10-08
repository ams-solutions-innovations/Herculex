import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';

/// Makes a phase's calories and macros the member's daily target.
///
/// The one write behind every "Apply" for a phase: the global target row the
/// diary reads, and the active plan the Profile and the target editor show.
/// Callers decide *when*; nothing here runs on its own.
class PhaseTargetsApplier {
  PhaseTargetsApplier(this._ref);

  final Ref _ref;

  Future<void> apply({
    required DietPhase phase,
    required DietPaceOption pace,
    required PhaseTargets targets,
  }) async {
    await _ref
        .read(nutritionRepositoryProvider)
        .upsertTarget(
          label: 'General (${phase.label})',
          appliesTo: 'global',
          kcal: targets.kcal,
          proteinG: targets.proteinG,
          carbsG: targets.carbsG,
          fatG: targets.fatG,
        );
    await _ref
        .read(activeDietPlanProvider.notifier)
        .setPlan(
          phase: phase,
          weeklyRateKg: pace.weeklyKg,
          kcalDelta: pace.kcalDelta,
          paceLabel: pace.label,
        );
  }
}

final phaseTargetsApplierProvider = Provider<PhaseTargetsApplier>(
  PhaseTargetsApplier.new,
);
