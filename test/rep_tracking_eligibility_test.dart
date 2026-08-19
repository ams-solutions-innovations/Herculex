import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';
import 'package:herculex/features/reps/domain/rep_tracking_eligibility.dart';
import 'package:herculex/features/reps/domain/rep_tracking_profile.dart';

/// Eligibility used to be a hand-maintained set of seven slugs. It is now
/// derived from the capability profiles asset, which covers the whole
/// catalogue — so these tests moved from "is this slug on the list" to "does
/// the physics of this exercise resolve to the right sensor site".
///
/// The asset's own internal consistency is `test/rep_tracking_profiles_test.dart`;
/// this file tests only the four lookup functions on top of it.
void main() {
  setUp(() {
    RepProfileRegistry.loadFromJson(
      File('assets/data/rep_tracking_profiles.json').readAsStringSync(),
    );
  });

  tearDown(RepProfileRegistry.resetForTest);

  group('isEligible', () {
    test('the original seven slugs are still eligible', () {
      // The pull-up and dip families were the whole of v1. Widening coverage
      // must not have dropped any of them.
      for (final slug in const [
        'pull-up',
        'pull-up-wide-grip',
        'pull-up-super-wide',
        'pull-up-neutral-grip',
        'chin-up-supinated',
        'chest-dips',
        'ring-dips',
      ]) {
        expect(isEligible(slug), isTrue, reason: slug);
      }
    });

    test('wrist-sensed barbell and dumbbell work is now eligible too', () {
      for (final slug in const [
        'barbell-bench-press',
        'dumbbell-curl',
        'barbell-back-squat',
        'conventional-deadlift',
        'lat-pulldown',
        'dumbbell-lateral-raise',
      ]) {
        expect(isEligible(slug), isTrue, reason: slug);
      }
    });

    test('exercises no sensor site can see stay ineligible', () {
      for (final slug in const [
        'seated-leg-curl',
        'leg-extension',
        'machine-neck-curl',
        'dumbbell-wrist-curl',
        'machine-abductor',
      ]) {
        expect(isEligible(slug), isFalse, reason: slug);
        expect(movementFor(slug), isNull, reason: slug);
        expect(sensorSiteFor(slug), isNull, reason: slug);
      }
    });

    test('non-rep-based exercises stay ineligible', () {
      for (final slug in const ['plank', 'farmers-walk', 'treadmill-run']) {
        final profile = profileFor(slug);
        if (profile == null) continue; // slug not in this catalogue revision
        expect(isEligible(slug), isFalse, reason: slug);
      }
    });
  });

  group('movementFor', () {
    test('the pull-up family maps to verticalPull', () {
      for (final slug in const [
        'pull-up',
        'pull-up-wide-grip',
        'pull-up-super-wide',
        'pull-up-neutral-grip',
        'chin-up-supinated',
      ]) {
        expect(movementFor(slug), RepMovement.verticalPull, reason: slug);
      }
    });

    test('dips map to bodyweightPush', () {
      expect(movementFor('chest-dips'), RepMovement.bodyweightPush);
      expect(movementFor('ring-dips'), RepMovement.bodyweightPush);
    });

    test('an inverted row is its own family, not a push', () {
      // Hands-anchored and hip-sensed like a push-up, but a different
      // acceleration shape — and the family is the calibration key, so
      // sharing one would train a single profile on two movements.
      expect(movementFor('barbell-inverted-row'), RepMovement.bodyweightPull);
      expect(movementFor('standard-push-up'), RepMovement.bodyweightPush);
    });

    test('a lat pulldown is not the same family as a pull-up', () {
      // Seated with the hands travelling versus hanging with the hands still.
      expect(movementFor('lat-pulldown'), RepMovement.verticalPullDown);
      expect(movementFor('pull-up'), RepMovement.verticalPull);
    });
  });

  group('sensorSiteFor', () {
    test('hands-anchored work needs the phone in a pocket', () {
      for (final slug in const [
        'pull-up',
        'chest-dips',
        'standard-push-up',
        'barbell-inverted-row',
        'hanging-leg-raise',
      ]) {
        expect(sensorSiteFor(slug), SensorSite.pocket, reason: slug);
      }
    });

    test('everything the hand carries is sensed at the wrist', () {
      for (final slug in const [
        'barbell-bench-press',
        'dumbbell-curl',
        'barbell-back-squat',
        'tricep-pushdown-rope',
      ]) {
        expect(sensorSiteFor(slug), SensorSite.wrist, reason: slug);
      }
    });
  });

  group('profileFor', () {
    test('carries a plain-language reason for every row', () {
      expect(profileFor('seated-leg-curl')!.reason, contains('femur'));
      expect(profileFor('pull-up')!.reason, contains('hands anchored'));
    });

    test('short-range work is countOnly and never carries an RPE', () {
      final shrug = profileFor('barbell-shrug')!;
      expect(shrug.tier, RepTrackingTier.countOnly);
      expect(shrug.isTrackable, isTrue);
      expect(shrug.supportsRpe, isFalse);
    });
  });

  group('unknown input', () {
    test('null is ineligible', () {
      expect(isEligible(null), isFalse);
      expect(profileFor(null), isNull);
      expect(sensorSiteFor(null), isNull);
    });

    test('slugs are exact — casing and whitespace are not normalised', () {
      expect(isEligible('Pull-Up'), isFalse);
      expect(isEligible(' pull-up'), isFalse);
      expect(isEligible(''), isFalse);
      expect(isEligible('some-custom-exercise'), isFalse);
    });
  });

  group('without a loaded registry', () {
    test('nothing is eligible', () {
      // The failure direction that matters: before the asset loads, and if it
      // ever fails to load, the feature is invisible rather than running on
      // guessed thresholds.
      RepProfileRegistry.resetForTest();

      expect(isEligible('pull-up'), isFalse);
      expect(isEligible('barbell-bench-press'), isFalse);
      expect(movementFor('pull-up'), isNull);
      expect(profileFor('pull-up'), isNull);
    });
  });
}
