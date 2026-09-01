import 'one_rep_max.dart';

/// Training goal driving rep targets and load progression (V2 §16).
enum ProgressionGoal {
  strength('Strength', repsMin: 3, repsMax: 6, weeklyIncreasePct: 2.5),
  muscleGain('Muscle Gain', repsMin: 8, repsMax: 12, weeklyIncreasePct: 2.5),
  fatLoss('Fat Loss', repsMin: 12, repsMax: 15, weeklyIncreasePct: 1.5),
  endurance('Endurance', repsMin: 15, repsMax: 20, weeklyIncreasePct: 1.0),
  athletic(
    'Athletic Performance',
    repsMin: 4,
    repsMax: 8,
    weeklyIncreasePct: 2.0,
  );

  const ProgressionGoal(
    this.label, {
    required this.repsMin,
    required this.repsMax,
    required this.weeklyIncreasePct,
  });

  final String label;
  final int repsMin;
  final int repsMax;

  /// Goal-specific default; the spec's global default of 5%/week is exposed
  /// as [ProgressionEngine.defaultWeeklyIncreasePct] and user-overridable.
  final double weeklyIncreasePct;
}

class SuggestedTarget {
  final double weightKg;
  final int reps;
  final String rationale;
  const SuggestedTarget({
    required this.weightKg,
    required this.reps,
    required this.rationale,
  });
}

/// Suggested next-workout targets from last performance (V2 §16). Barbell
/// loads round to what plates can actually build; other equipment rounds to
/// typical increments.
class ProgressionEngine {
  /// Spec default: +5% weight per week, user-configurable.
  static const defaultWeeklyIncreasePct = 5.0;

  /// Smallest total barbell increment from the available plate set
  /// (1.25 kg per side).
  static const barbellStepKg = 2.5;
  static const dumbbellStepKg = 2.0;
  static const machineStepKg = 2.5;

  static double stepFor(String equipmentVariant) => switch (equipmentVariant) {
    'barbell' || 'smith' => barbellStepKg,
    'dumbbell' || 'kettlebell' => dumbbellStepKg,
    _ => machineStepKg,
  };

  /// Next target from the best working set of the last session.
  ///
  /// Inside the goal's rep range: add reps first when below max, otherwise
  /// add load (the configured weekly % of current weight, plate-rounded) and
  /// reset to the bottom of the range — double progression.
  static SuggestedTarget suggestNext({
    required double lastWeightKg,
    required int lastReps,
    required ProgressionGoal goal,
    required String equipmentVariant,
    double? weeklyIncreasePctOverride,
  }) {
    final step = stepFor(equipmentVariant);

    if (lastWeightKg <= 0) {
      return SuggestedTarget(
        weightKg: 0,
        reps: lastReps < goal.repsMax ? lastReps + 1 : lastReps,
        rationale: 'Add a rep — no load to progress yet.',
      );
    }

    if (lastReps < goal.repsMax) {
      return SuggestedTarget(
        weightKg: lastWeightKg,
        reps: lastReps + 1,
        rationale:
            'Same load, one more rep (${goal.label} range ${goal.repsMin}–${goal.repsMax}).',
      );
    }

    final pct = weeklyIncreasePctOverride ?? goal.weeklyIncreasePct;
    final raw = lastWeightKg * (1 + pct / 100);
    var next = roundToNearest(raw, step);
    // A %-increase smaller than one plate step still has to move the bar.
    if (next <= lastWeightKg) next = lastWeightKg + step;

    return SuggestedTarget(
      weightKg: next,
      reps: goal.repsMin,
      rationale:
          'Top of rep range hit — +${pct.toStringAsFixed(1)}% load, back to ${goal.repsMin} reps.',
    );
  }
}
