import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/effective_load.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';

void main() {
  group('LiveWorkoutStats tests', () {
    test('default constructor initializes with zero values', () {
      const stats = LiveWorkoutStats();
      expect(stats.totalSets, equals(0));
      expect(stats.completedSets, equals(0));
      expect(stats.totalTonnageKg, equals(0.0));
    });

    test(
      'calculates tonnage correctly with EffectiveLoad and SetType factors',
      () {
        final set1Effective = EffectiveLoad.computeKg(weightKg: 100);
        final set1Tonnage = EffectiveLoad.tonnageKg(
          effectiveKg: set1Effective,
          reps: 5,
          setType: SetType.standard,
        );

        final set2Effective = EffectiveLoad.computeKg(weightKg: 120);
        final set2Tonnage = EffectiveLoad.tonnageKg(
          effectiveKg: set2Effective,
          reps: 3,
          setType: SetType.standard,
        );

        final set3Effective = EffectiveLoad.computeKg(weightKg: 80);
        final set3Tonnage = EffectiveLoad.tonnageKg(
          effectiveKg: set3Effective,
          reps: 8,
          setType: SetType.drop,
        );

        final totalTonnage = set1Tonnage + set2Tonnage + set3Tonnage;
        expect(totalTonnage, equals(500.0 + 360.0 + 640.0));

        final stats = LiveWorkoutStats(
          totalSets: 3,
          completedSets: 3,
          totalTonnageKg: totalTonnage,
        );

        expect(stats.totalSets, equals(3));
        expect(stats.completedSets, equals(3));
        expect(stats.totalTonnageKg, equals(1500.0));

        const weightFormat = WeightFormat(MeasurementUnit.metric);
        expect(
          weightFormat.formatTonnage(stats.totalTonnageKg),
          equals('1.5 t'),
        );
      },
    );

    test('formats tonnage under 1000 kg as kg', () {
      const stats = LiveWorkoutStats(
        totalSets: 2,
        completedSets: 1,
        totalTonnageKg: 450.0,
      );
      const weightFormat = WeightFormat(MeasurementUnit.metric);
      expect(
        weightFormat.formatTonnage(stats.totalTonnageKg),
        equals('450 kg'),
      );
    });
  });
}
