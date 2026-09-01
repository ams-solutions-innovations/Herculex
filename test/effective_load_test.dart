import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/effective_load.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

void main() {
  group('EffectiveLoad.computeKg', () {
    test('plain barbell set is just the bar weight', () {
      expect(EffectiveLoad.computeKg(weightKg: 100), 100);
    });

    test('weighted bodyweight includes the BW snapshot', () {
      expect(
        EffectiveLoad.computeKg(
          weightKg: 25,
          bodyweightKg: 80,
          includesBodyweight: true,
        ),
        105,
      );
    });

    test('bodyweight ignored when exercise does not support it', () {
      expect(EffectiveLoad.computeKg(weightKg: 25, bodyweightKg: 80), 25);
    });

    test('resistance bands add half their rated tension per band', () {
      // 2 × 20kg green bands as resistance → +20kg average.
      expect(
        EffectiveLoad.computeKg(
          weightKg: 100,
          bands: const [
            BandContribution(tensionKg: 20, count: 2, isResistance: true),
          ],
        ),
        120,
      );
    });

    test('assistance bands subtract', () {
      expect(
        EffectiveLoad.computeKg(
          weightKg: 0,
          bodyweightKg: 80,
          includesBodyweight: true,
          bands: const [BandContribution(tensionKg: 30, isResistance: false)],
        ),
        65,
      );
    });

    test('chains add their pre-averaged contribution', () {
      expect(EffectiveLoad.computeKg(weightKg: 100, chainsKg: 10), 110);
    });

    test('never goes negative under heavy assistance', () {
      expect(
        EffectiveLoad.computeKg(
          weightKg: 0,
          bands: const [BandContribution(tensionKg: 100, isResistance: false)],
        ),
        0,
      );
    });
  });

  group('EffectiveLoad.tonnageKg', () {
    test('standard set is load × reps', () {
      expect(EffectiveLoad.tonnageKg(effectiveKg: 100, reps: 5), 500);
    });

    test('partials count half volume', () {
      expect(
        EffectiveLoad.tonnageKg(
          effectiveKg: 100,
          reps: 10,
          setType: SetType.partials,
        ),
        500,
      );
    });
  });

  group('SetType registry', () {
    test('round-trips every id through fromId', () {
      for (final t in SetType.values) {
        expect(SetType.fromId(t.id), t);
      }
    });

    test('unknown or null id falls back to standard', () {
      expect(SetType.fromId('definitely_not_a_type'), SetType.standard);
      expect(SetType.fromId(null), SetType.standard);
    });

    test('historic sets keep tonnage unchanged (standard factor = 1)', () {
      expect(SetType.standard.volumeFactor, 1.0);
      expect(SetType.standard.cnsFactor, 1.0);
    });

    test('myoReps has standard volumeFactor of 1.0 and cnsFactor 1.0', () {
      expect(SetType.myoReps.volumeFactor, 1.0);
      expect(SetType.myoReps.cnsFactor, 1.0);
    });
  });
}
