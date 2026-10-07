import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/domain/anthropometry.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  group('AnthropometryRatios', () {
    test('calculates correct proportions for average build', () {
      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        heightCm: 180,
        inseamCm: 82.8, // 82.8 / 180 = 0.46 (Average)
        armSpanCm: 180, // 180 / 180 = 1.0 (Average)
        torsoCm: 61.2, // 61.2 / 180 = 0.34 (Average)
      );

      final ratios = AnthropometryRatios(profile);

      expect(ratios.hasRequiredMeasurements, isTrue);
      expect(ratios.apeIndex, closeTo(1.0, 0.001));
      expect(ratios.legToHeightRatio, closeTo(0.46, 0.001));
      expect(ratios.torsoToHeightRatio, closeTo(0.34, 0.001));

      expect(ratios.armProportion, ArmProportion.average);
      expect(ratios.legProportion, LegProportion.average);
      expect(ratios.torsoProportion, TorsoProportion.average);
    });

    test('calculates correct proportions for short build', () {
      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        heightCm: 180,
        inseamCm: 77.4, // 77.4 / 180 = 0.43 (Short)
        armSpanCm: 174.6, // 174.6 / 180 = 0.97 (Short)
        torsoCm: 55.8, // 55.8 / 180 = 0.31 (Short)
      );

      final ratios = AnthropometryRatios(profile);

      expect(ratios.armProportion, ArmProportion.short);
      expect(ratios.legProportion, LegProportion.short);
      expect(ratios.torsoProportion, TorsoProportion.short);
    });

    test('calculates correct proportions for long build', () {
      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        heightCm: 180,
        inseamCm: 88.2, // 88.2 / 180 = 0.49 (Long)
        armSpanCm: 185.4, // 185.4 / 180 = 1.03 (Long)
        torsoCm: 66.6, // 66.6 / 180 = 0.37 (Long)
      );

      final ratios = AnthropometryRatios(profile);

      expect(ratios.armProportion, ArmProportion.long);
      expect(ratios.legProportion, LegProportion.long);
      expect(ratios.torsoProportion, TorsoProportion.long);
    });

    test('returns null when measurements are missing', () {
      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        heightCm: 180,
        // Missing inseam, armSpan, torso
      );

      final ratios = AnthropometryRatios(profile);

      expect(ratios.hasRequiredMeasurements, isFalse);
      expect(ratios.apeIndex, isNull);
      expect(ratios.legToHeightRatio, isNull);
      expect(ratios.torsoToHeightRatio, isNull);
      expect(ratios.armProportion, isNull);
      expect(ratios.legProportion, isNull);
      expect(ratios.torsoProportion, isNull);
    });
  });
}
