import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Independent copy of the legacy `MacroTargets.fromProfile` formula, kept here
/// verbatim so the refactor into bmr / multiplierFor / goalDeltaKcal /
/// fromMaintenance can be proven byte-identical.
MacroTargets _legacy(Profile p) {
  final w = p.weightKg!;
  final h = p.heightCm!;
  final a = p.ageYears!;
  final offset = (p.sex == BiologicalSex.female) ? -161 : 5;
  final bmr = 10 * w + 6.25 * h - 5 * a + offset;
  final multiplier = switch (p.activityLevel) {
    ActivityLevel.sedentary => 1.2,
    ActivityLevel.lightlyActive => 1.375,
    ActivityLevel.active => 1.55,
    ActivityLevel.veryActive => 1.725,
  };
  final tdee = bmr * multiplier;
  final adjusted =
      tdee +
      switch (p.goal) {
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

Profile _profile({
  ActivityLevel activity = ActivityLevel.active,
  FitnessGoal goal = FitnessGoal.maintenance,
  BiologicalSex sex = BiologicalSex.male,
  double? weightKg = 80,
  double? heightCm = 180,
  int? ageYears = 28,
}) => Profile(
  goal: goal,
  activityLevel: activity,
  sex: sex,
  weightKg: weightKg,
  heightCm: heightCm,
  ageYears: ageYears,
);

void _expectSame(MacroTargets? actual, MacroTargets expected, String label) {
  expect(actual, isNotNull, reason: label);
  expect(actual!.kcal, expected.kcal, reason: '$label kcal');
  expect(actual.proteinG, expected.proteinG, reason: '$label protein');
  expect(actual.carbsG, expected.carbsG, reason: '$label carbs');
  expect(actual.fatG, expected.fatG, reason: '$label fat');
}

void main() {
  group('MacroTargets.fromProfile characterization', () {
    test('matches the legacy formula for every level x goal x sex', () {
      for (final level in ActivityLevel.values) {
        for (final goal in FitnessGoal.values) {
          for (final sex in BiologicalSex.values) {
            final p = _profile(activity: level, goal: goal, sex: sex);
            _expectSame(
              MacroTargets.fromProfile(p),
              _legacy(p),
              '${level.name}/${goal.name}/${sex.name}',
            );
          }
        }
      }
    });

    test('returns null when weight, height or age is missing', () {
      expect(MacroTargets.fromProfile(_profile(weightKg: null)), isNull);
      expect(MacroTargets.fromProfile(_profile(heightCm: null)), isNull);
      expect(MacroTargets.fromProfile(_profile(ageYears: null)), isNull);
    });
  });

  group('shared maintenance pieces', () {
    test('multiplierFor returns the four activity multipliers', () {
      expect(MacroTargets.multiplierFor(ActivityLevel.sedentary), 1.2);
      expect(MacroTargets.multiplierFor(ActivityLevel.lightlyActive), 1.375);
      expect(MacroTargets.multiplierFor(ActivityLevel.active), 1.55);
      expect(MacroTargets.multiplierFor(ActivityLevel.veryActive), 1.725);
    });

    test('goalDeltaKcal is -500 / +300 / 0 / 0', () {
      expect(MacroTargets.goalDeltaKcal(FitnessGoal.weightLoss), -500);
      expect(MacroTargets.goalDeltaKcal(FitnessGoal.muscleGain), 300);
      expect(MacroTargets.goalDeltaKcal(FitnessGoal.maintenance), 0);
      expect(MacroTargets.goalDeltaKcal(FitnessGoal.improveHealth), 0);
    });

    test('bmr is Mifflin-St Jeor with the sex offset', () {
      expect(MacroTargets.bmr(_profile(sex: BiologicalSex.male)), 1790);
      expect(MacroTargets.bmr(_profile(sex: BiologicalSex.female)), 1624);
      expect(MacroTargets.bmr(_profile(weightKg: null)), isNull);
      expect(MacroTargets.bmr(_profile(heightCm: null)), isNull);
      expect(MacroTargets.bmr(_profile(ageYears: null)), isNull);
    });

    test('seedMaintenanceKcal is bmr x multiplier, null without metrics', () {
      for (final level in ActivityLevel.values) {
        final p = _profile(activity: level);
        expect(
          MacroTargets.seedMaintenanceKcal(p),
          closeTo(1790 * MacroTargets.multiplierFor(level), 1e-9),
        );
      }
      expect(
        MacroTargets.seedMaintenanceKcal(_profile(weightKg: null)),
        isNull,
      );
    });
  });

  group('MacroTargets.fromMaintenance', () {
    test('applies the goal delta exactly once', () {
      final gain = MacroTargets.fromMaintenance(
        _profile(goal: FitnessGoal.muscleGain),
        2500,
      );
      final loss = MacroTargets.fromMaintenance(
        _profile(goal: FitnessGoal.weightLoss),
        2500,
      );
      final keep = MacroTargets.fromMaintenance(
        _profile(goal: FitnessGoal.maintenance),
        2500,
      );
      expect(gain!.kcal, 2800);
      expect(loss!.kcal, 2000);
      expect(keep!.kcal, 2500);
    });

    test('macro split: 1.8 g/kg protein, 27.5% fat, remainder carbs', () {
      final t = MacroTargets.fromMaintenance(
        _profile(goal: FitnessGoal.muscleGain),
        2500,
      )!;
      const adjusted = 2800.0;
      final protein = (80 * 1.8).round();
      final fatKcal = adjusted * 0.275;
      expect(t.proteinG, protein);
      expect(t.fatG, (fatKcal / 9).round());
      expect(
        t.carbsG,
        ((adjusted - protein * 4 - fatKcal) / 4).round().clamp(0, 1000),
      );
    });

    test('carbs are clamped to [0, 1000]', () {
      final low = MacroTargets.fromMaintenance(_profile(), 300)!;
      expect(low.carbsG, 0);
      final high = MacroTargets.fromMaintenance(_profile(), 20000)!;
      expect(high.carbsG, 1000);
    });

    test('returns null when weight is missing', () {
      expect(
        MacroTargets.fromMaintenance(_profile(weightKg: null), 2500),
        isNull,
      );
    });

    test('fromProfile == fromMaintenance(seedMaintenanceKcal) everywhere', () {
      for (final level in ActivityLevel.values) {
        for (final goal in FitnessGoal.values) {
          for (final sex in BiologicalSex.values) {
            final p = _profile(activity: level, goal: goal, sex: sex);
            _expectSame(
              MacroTargets.fromMaintenance(
                p,
                MacroTargets.seedMaintenanceKcal(p)!,
              ),
              MacroTargets.fromProfile(p)!,
              '${level.name}/${goal.name}/${sex.name}',
            );
          }
        }
      }
    });
  });
}
