import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/programs/domain/volume_bands.dart';

void main() {
  group('priors', () {
    test('every tracked muscle group has a band', () {
      for (final group in MuscleRecoveryV3.groups) {
        expect(
          VolumeBands.priors.containsKey(group),
          isTrue,
          reason: '$group has no volume prior',
        );
      }
    });

    test('bands are ordered minimum < adaptive < maximum', () {
      VolumeBands.priors.forEach((group, band) {
        expect(band.$1, lessThan(band.$2), reason: group);
        expect(band.$2, lessThan(band.$3), reason: group);
      });
    });

    test('an unknown group falls back instead of throwing', () {
      final band = VolumeBands.forGroup('Gills');
      expect(band.minimum, greaterThan(0));
      expect(band.personalized, isFalse);
    });
  });

  group('verdicts', () {
    final chest = VolumeBands.forGroup('Chest');

    test('reads the four states in order', () {
      expect(chest.verdict(chest.minimum - 1), VolumeVerdict.low);
      expect(chest.verdict(chest.minimum), VolumeVerdict.good);
      expect(chest.verdict(chest.adaptive), VolumeVerdict.good);
      expect(chest.verdict(chest.adaptive + 1), VolumeVerdict.high);
      expect(chest.verdict(chest.maximum), VolumeVerdict.high);
      expect(chest.verdict(chest.maximum + 1), VolumeVerdict.tooMuch);
    });

    test('the bar fill saturates instead of overflowing', () {
      expect(chest.fill(0), 0);
      expect(chest.fill(chest.maximum * 10), 1.0);
      expect(chest.fill(chest.adaptive), inInclusiveRange(0.0, 1.0));
    });

    test('labels never mention MEV or MRV', () {
      for (final v in VolumeVerdict.values) {
        expect(v.label.toUpperCase(), isNot(contains('MEV')));
        expect(v.label.toUpperCase(), isNot(contains('MRV')));
        expect(v.label, isNotEmpty);
      }
    });
  });

  group('personalization', () {
    test('one week of data barely moves the band', () {
      final prior = VolumeBands.forGroup('Chest');
      final nudged = VolumeBands.forGroup(
        'Chest',
        tolerance: const VolumeTolerance(weeksObserved: 1, sustainedSets: 40),
      );
      expect(nudged.maximum - prior.maximum, lessThan(6));
      expect(nudged.personalized, isFalse);
    });

    test('sustained history pulls the band toward the user', () {
      final prior = VolumeBands.forGroup('Chest');
      final earned = VolumeBands.forGroup(
        'Chest',
        tolerance: const VolumeTolerance(weeksObserved: 20, sustainedSets: 34),
      );
      expect(earned.maximum, greaterThan(prior.maximum));
      expect(earned.maximum, lessThan(34 + 1));
      expect(earned.personalized, isTrue);
    });

    test('a low tolerance lowers the ceiling too', () {
      final prior = VolumeBands.forGroup('Quads');
      final limited = VolumeBands.forGroup(
        'Quads',
        tolerance: const VolumeTolerance(weeksObserved: 20, sustainedSets: 10),
      );
      expect(limited.maximum, lessThan(prior.maximum));
      expect(limited.minimum, lessThan(prior.minimum));
    });

    test('the band keeps its shape when it moves', () {
      final band = VolumeBands.forGroup(
        'Chest',
        tolerance: const VolumeTolerance(weeksObserved: 30, sustainedSets: 30),
      );
      expect(band.minimum, lessThan(band.adaptive));
      expect(band.adaptive, lessThan(band.maximum));
    });

    test('zero observed weeks is treated as no data', () {
      final prior = VolumeBands.forGroup('Chest');
      final empty = VolumeBands.forGroup(
        'Chest',
        tolerance: const VolumeTolerance(weeksObserved: 0, sustainedSets: 99),
      );
      expect(empty.maximum, prior.maximum);
    });
  });

  group('verdicts()', () {
    test('maps a whole week of planned volume at once', () {
      final result = VolumeBands.verdicts({
        'Chest': 4,
        'Back': 18,
        'Quads': 40,
      });
      expect(result['Chest'], VolumeVerdict.low);
      expect(result['Back'], VolumeVerdict.good);
      expect(result['Quads'], VolumeVerdict.tooMuch);
    });
  });
}
