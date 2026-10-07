import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';

void main() {
  group('MinimumTargetsState & resolvedMinProteinG', () {
    test('returns null when minimum targets disabled', () {
      const state = MinimumTargetsState(
        enabled: false,
        mode: MinProteinMode.perLb,
        proteinValue: 1.0,
      );
      expect(state.resolvedMinProteinG(80.0), isNull);
    });

    test('calculates g/lb protein floor from bodyweight correctly', () {
      const state = MinimumTargetsState(
        enabled: true,
        mode: MinProteinMode.perLb,
        proteinValue: 1.0,
      );
      // 80 kg = 176.3696 lbs -> ~176 g protein @ 1.0 g/lb
      final minP = state.resolvedMinProteinG(80.0);
      expect(minP, 176);
    });

    test('calculates 1.2 g/lb high protein floor correctly', () {
      const state = MinimumTargetsState(
        enabled: true,
        mode: MinProteinMode.perLb,
        proteinValue: 1.2,
      );
      // 80 kg = 176.3696 lbs * 1.2 = 211.64 -> 212 g
      final minP = state.resolvedMinProteinG(80.0);
      expect(minP, 212);
    });

    test('calculates g/kg protein floor correctly', () {
      const state = MinimumTargetsState(
        enabled: true,
        mode: MinProteinMode.perKg,
        proteinValue: 2.2,
      );
      // 80 kg * 2.2 = 176 g
      final minP = state.resolvedMinProteinG(80.0);
      expect(minP, 176);
    });

    test('calculates fixed protein floor correctly', () {
      const state = MinimumTargetsState(
        enabled: true,
        mode: MinProteinMode.fixed,
        proteinValue: 180.0,
      );
      final minP = state.resolvedMinProteinG(null);
      expect(minP, 180);
    });

    test('effectiveMinCaloriesKcal respects enabled flag', () {
      const disabled = MinimumTargetsState(
        enabled: false,
        minCaloriesKcal: 1500,
      );
      expect(disabled.effectiveMinCaloriesKcal, isNull);

      const enabled = MinimumTargetsState(enabled: true, minCaloriesKcal: 1500);
      expect(enabled.effectiveMinCaloriesKcal, 1500);
    });
  });
}
