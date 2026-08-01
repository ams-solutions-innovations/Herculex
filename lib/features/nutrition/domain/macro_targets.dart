import '../../profile/domain/profile.dart';

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

  /// Returns null when profile lacks the body metrics we need (weight/height/age).
  /// Calorie target uses Mifflin-St Jeor BMR × activity multiplier, with a goal
  /// adjustment (−500 / +300 / 0). Macro split: 1.8 g/kg protein, 27.5% fat, rest carbs.
  /// Assumes male; sex isn't captured in onboarding yet, and the variance is
  /// small enough for personal use until that data point is added.
  static MacroTargets? fromProfile(Profile profile) {
    final w = profile.weightKg;
    final h = profile.heightCm;
    final a = profile.ageYears;
    if (w == null || h == null || a == null) return null;

    // Mifflin-St Jeor formula based on sex. Defaults to male offset (+5) if sex is unset.
    final offset = (profile.sex == BiologicalSex.female) ? -161 : 5;
    final bmr = 10 * w + 6.25 * h - 5 * a + offset;
    final multiplier = switch (profile.activityLevel) {
      ActivityLevel.sedentary => 1.2,
      ActivityLevel.lightlyActive => 1.375,
      ActivityLevel.active => 1.55,
      ActivityLevel.veryActive => 1.725,
    };
    final tdee = bmr * multiplier;
    final adjusted =
        tdee +
        switch (profile.goal) {
          FitnessGoal.weightLoss => -500,
          FitnessGoal.muscleGain => 300,
          FitnessGoal.maintenance => 0,
          FitnessGoal.improveHealth => 0,
        };

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
}
