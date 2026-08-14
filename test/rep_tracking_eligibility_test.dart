import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';
import 'package:herculex/features/reps/domain/rep_tracking_eligibility.dart';

void main() {
  group('eligibleRepSlugs', () {
    test('holds exactly the seven slugs from 10-CONTEXT', () {
      expect(eligibleRepSlugs.length, 7);
      expect(eligibleRepSlugs, {
        'pull-up',
        'pull-up-wide-grip',
        'pull-up-super-wide',
        'pull-up-neutral-grip',
        'chin-up-supinated',
        'chest-dips',
        'ring-dips',
      });
    });

    test('every listed slug is eligible', () {
      for (final slug in eligibleRepSlugs) {
        expect(isEligible(slug), isTrue, reason: '$slug should be eligible');
      }
    });
  });

  group('movementFor', () {
    test('maps the five pull-up/chin-up slugs to pullUp', () {
      for (final slug in const [
        'pull-up',
        'pull-up-wide-grip',
        'pull-up-super-wide',
        'pull-up-neutral-grip',
        'chin-up-supinated',
      ]) {
        expect(movementFor(slug), RepMovement.pullUp, reason: slug);
      }
    });

    test('maps chest-dips and ring-dips to dip', () {
      expect(movementFor('chest-dips'), RepMovement.dip);
      expect(movementFor('ring-dips'), RepMovement.dip);
    });

    test('every eligible slug has a movement', () {
      for (final slug in eligibleRepSlugs) {
        expect(movementFor(slug), isNotNull, reason: slug);
      }
    });
  });

  group('deliberate exclusions stay excluded', () {
    // Widening this list without new fixture traces is exactly the failure
    // mode this test exists to catch (REP-06).
    const excluded = <String>[
      'assisted-pull-up-machine-wide-grip',
      'band-assisted-dip',
      'negative-pull-up',
      'scapular-pull-up',
      'bench-dip',
      'trx-hanging-dip',
      'typewriter-pull-up',
      'commando-pull-up',
      'behind-the-neck-pull-up',
      'towel-pull-up',
      'ring-l-sit-pull-up',
    ];

    test('are ineligible and have a null movement', () {
      for (final slug in excluded) {
        expect(isEligible(slug), isFalse, reason: '$slug must be ineligible');
        expect(movementFor(slug), isNull, reason: '$slug must have no movement');
      }
    });
  });

  group('unknown input', () {
    test('null is ineligible', () {
      expect(isEligible(null), isFalse);
    });

    test('an unknown slug is ineligible with a null movement', () {
      expect(isEligible('barbell-bench-press'), isFalse);
      expect(movementFor('barbell-bench-press'), isNull);
      // Casing and whitespace are not normalised — slugs are exact.
      expect(isEligible('Pull-Up'), isFalse);
      expect(isEligible(' pull-up'), isFalse);
      expect(isEligible(''), isFalse);
    });
  });
}
