import 'package:herculex/features/profile/domain/profile.dart';

class MacroTargets {
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;

  const MacroTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  /// Mifflin-St Jeor basal metabolic rate. Uses the female offset (-161) when
  /// [Profile.sex] is female, otherwise the male offset (+5). Returns null when
  /// the profile lacks weight, height or age.
  static double? bmr(Profile profile) {
    final w = profile.weightKg;
    final h = profile.heightCm;
    final a = profile.ageYears;
    if (w == null || h == null || a == null) return null;
    final offset = (profile.sex == BiologicalSex.female) ? -161 : 5;
    return 10 * w + 6.25 * h - 5 * a + offset;
  }

  /// Hand-picked activity multiplier for an onboarding [ActivityLevel]. This is
  /// the cold-start seed and the manual reseed value for adaptive TDEE.
  static double multiplierFor(ActivityLevel level) => switch (level) {
    ActivityLevel.sedentary => 1.2,
    ActivityLevel.lightlyActive => 1.375,
    ActivityLevel.active => 1.55,
    ActivityLevel.veryActive => 1.725,
  };

  /// Daily calorie adjustment for a goal: -500 / +300 / 0. Referenced only from
  /// [fromMaintenance] so the delta can never be applied twice.
  static int goalDeltaKcal(FitnessGoal goal) => switch (goal) {
    FitnessGoal.weightLoss => -500,
    FitnessGoal.muscleGain => 300,
    FitnessGoal.maintenance => 0,
    FitnessGoal.improveHealth => 0,
  };

  /// Pure maintenance calories from the profile alone: BMR x the onboarding
  /// activity multiplier, with no goal adjustment. Null when metrics are missing.
  static double? seedMaintenanceKcal(Profile profile) {
    final base = bmr(profile);
    if (base == null) return null;
    return base * multiplierFor(profile.activityLevel);
  }

  /// Turns a PURE maintenance figure (measured or classified TDEE, never
  /// already goal-adjusted) into a goal-adjusted, macro-split target. This is
  /// the single place the goal delta is added, and the single place the macro
  /// split lives: 1.8 g/kg protein, 27.5% of kcal from fat, remainder carbs.
  /// Returns null when [Profile.weightKg] is missing.
  static MacroTargets? fromMaintenance(
    Profile profile,
    double maintenanceKcal,
  ) {
    final w = profile.weightKg;
    if (w == null) return null;

    final adjusted = maintenanceKcal + goalDeltaKcal(profile.goal);

    final protein = (w * 1.8).round();
    final fatKcal = adjusted * 0.275;
    final fat = (fatKcal / 9).round();
    final carbsKcal = adjusted - (protein * 4) - fatKcal;
    final carbs = (carbsKcal / 4).round().clamp(0, 1000).toInt();

    return MacroTargets(
      kcal: adjusted.round(),
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );
  }

  /// Returns null when profile lacks the body metrics we need (weight/height/age).
  /// Calorie target uses Mifflin-St Jeor BMR x activity multiplier, with a goal
  /// adjustment (-500 / +300 / 0). Macro split: 1.8 g/kg protein, 27.5% fat, rest
  /// carbs. BMR uses [Profile.sex] (male offset when unset).
  static MacroTargets? fromProfile(Profile profile) {
    final seed = seedMaintenanceKcal(profile);
    return seed == null ? null : fromMaintenance(profile, seed);
  }
}
