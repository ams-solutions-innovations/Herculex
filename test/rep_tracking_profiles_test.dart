import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/rep_detector.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';
import 'package:herculex/features/reps/domain/rep_tracking_eligibility.dart';
import 'package:herculex/features/reps/domain/rep_tracking_profile.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';

/// Keeps four things that must agree from drifting apart: the exercise
/// catalogue, the generated capability profiles, the [RepMovement] enum and
/// the detector's per-family fallback thresholds.
///
/// The generator (`tool/derive_rep_profiles.py`) is not run by CI, so the
/// asset is a committed artefact. These tests are what makes that safe: a
/// catalogue row added without regenerating fails here, loudly, rather than
/// silently reporting as unsupported at runtime.
void main() {
  late List<Map<String, dynamic>> catalog;
  late List<Map<String, dynamic>> profiles;

  setUpAll(() {
    catalog = (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();
    profiles = (jsonDecode(
      File('assets/data/rep_tracking_profiles.json').readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  });

  group('coverage', () {
    test('every catalogue slug has exactly one profile', () {
      final catalogSlugs = catalog.map((e) => e['slug'] as String).toSet();
      final profileSlugs = profiles.map((e) => e['slug'] as String).toList();

      expect(
        profileSlugs.toSet().difference(catalogSlugs),
        isEmpty,
        reason: 'profiles exist for slugs not in the catalogue — regenerate',
      );
      expect(
        catalogSlugs.difference(profileSlugs.toSet()),
        isEmpty,
        reason: 'catalogue rows with no profile — run tool/derive_rep_profiles.py --write',
      );
      expect(
        profileSlugs.length,
        profileSlugs.toSet().length,
        reason: 'duplicate slug in the profiles asset',
      );
    });
  });

  group('internal coherence', () {
    test('every family names a real RepMovement', () {
      for (final raw in profiles) {
        final family = raw['family'] as String?;
        if (family == null) continue;
        expect(
          RepMovement.fromId(family),
          isNotNull,
          reason: '${raw['slug']} names unknown family "$family"',
        );
      }
    });

    test('a trackable profile carries a site, a family and thresholds', () {
      for (final raw in profiles) {
        final profile = RepTrackingProfile.fromJson(raw);
        if (!profile.isTrackable) continue;
        expect(profile.site, isNotNull, reason: profile.slug);
        expect(profile.family, isNotNull, reason: profile.slug);
        expect(profile.channels, isNotEmpty, reason: profile.slug);
        expect(profile.minPeriodMs, isNotNull, reason: profile.slug);
        expect(profile.maxPeriodMs, isNotNull, reason: profile.slug);
        expect(
          profile.minPeriodMs!,
          lessThan(profile.maxPeriodMs!),
          reason: profile.slug,
        );
      }
    });

    test('an unsupported profile carries no thresholds to borrow', () {
      // The whole point of stripping them: a caller that ignores the tier and
      // reaches for a threshold gets a null, not a neighbouring family's
      // numbers.
      for (final raw in profiles) {
        final profile = RepTrackingProfile.fromJson(raw);
        if (profile.isTrackable) continue;
        expect(profile.site, isNull, reason: profile.slug);
        expect(profile.family, isNull, reason: profile.slug);
        expect(profile.channels, isEmpty, reason: profile.slug);
        expect(profile.minPeriodMs, isNull, reason: profile.slug);
        expect(profile.maxPeriodMs, isNull, reason: profile.slug);
      }
    });

    test('every profile states a reason', () {
      for (final raw in profiles) {
        expect(
          RepTrackingProfile.fromJson(raw).reason,
          isNotEmpty,
          reason: '${raw['slug']} has no justification',
        );
      }
    });

    test('the amplitude floor matching each channel is present', () {
      for (final raw in profiles) {
        final profile = RepTrackingProfile.fromJson(raw);
        if (profile.channels.contains(RepChannel.dyn)) {
          expect(profile.minCycleAmplitudeMs2, isNotNull, reason: profile.slug);
        }
        if (profile.channels.contains(RepChannel.tilt) ||
            profile.channels.contains(RepChannel.rot)) {
          expect(profile.minCycleAmplitudeDeg, isNotNull, reason: profile.slug);
        }
      }
    });
  });

  group('physical invariants', () {
    test('nothing that is not rep-based is trackable', () {
      final metricBySlug = {
        for (final e in catalog)
          e['slug'] as String: LoggingMetric.fromId(e['loggingMetric'] as String?),
      };

      for (final raw in profiles) {
        final profile = RepTrackingProfile.fromJson(raw);
        if (!profile.isTrackable) continue;
        expect(
          metricBySlug[profile.slug]!.isRepBased,
          isTrue,
          reason: '${profile.slug} is trackable but is not logged in reps',
        );
      }
    });

    test('hands-anchored work is pocket-sited, never wrist-sited', () {
      // The user-visible half of the whole taxonomy: on a pull-up the hand
      // grips a fixed bar and the body travels past it, so the watch sees
      // almost nothing and the phone on the thigh sees everything.
      const handsAnchored = {
        'pull-up',
        'chin-up-supinated',
        'chest-dips',
        'ring-dips',
        'standard-push-up',
        'barbell-inverted-row',
        'hanging-leg-raise',
        'toes-to-bar',
      };

      for (final slug in handsAnchored) {
        final profile = RepTrackingProfile.fromJson(
          profiles.firstWhere((p) => p['slug'] == slug),
        );
        expect(profile.site, SensorSite.pocket, reason: slug);
        expect(profile.tier, RepTrackingTier.pocketOnly, reason: slug);
      }
    });

    test('exercises where neither segment moves are permanently unsupported', () {
      // Each of these is a physical exclusion, not a backlog item. A seated
      // leg curl straps the femur down and moves only the shin; the hands
      // rest on the handles. There is no sensor site that sees the rep.
      const impossible = {
        'seated-leg-curl',
        'lying-leg-curl',
        'leg-extension',
        'seated-calf-raise',
        'machine-abductor',
        'machine-adductor',
        'machine-neck-curl',
        'dumbbell-wrist-curl',
        'plank',
      };

      for (final slug in impossible) {
        final profile = RepTrackingProfile.fromJson(
          profiles.firstWhere((p) => p['slug'] == slug),
        );
        expect(profile.tier, RepTrackingTier.unsupported, reason: slug);
        expect(profile.reason, isNotEmpty, reason: slug);
      }
    });

    test('short-range work is countOnly, so it can never carry an RPE', () {
      for (final slug in ['barbell-shrug', 'standing-calf-raise', 'rack-pull-above-knee']) {
        final profile = RepTrackingProfile.fromJson(
          profiles.firstWhere((p) => p['slug'] == slug),
        );
        expect(profile.tier, RepTrackingTier.countOnly, reason: slug);
        expect(profile.supportsRpe, isFalse, reason: slug);
        expect(profile.family, RepMovement.smallRom, reason: slug);
      }
    });

    test('a name containing "neck" does not by itself disqualify an exercise', () {
      // Regression pin. A name-regex draft of the classifier put
      // behind-neck-pulldown and behind-the-neck-ohp in the unsupported
      // bucket purely on the substring, which is why classification runs over
      // movementPattern/modality/primaryMuscle and never over the name.
      for (final slug in ['behind-neck-pulldown', 'behind-the-neck-ohp']) {
        final profile = RepTrackingProfile.fromJson(
          profiles.firstWhere((p) => p['slug'] == slug),
        );
        expect(profile.tier, RepTrackingTier.supported, reason: slug);
        expect(profile.site, SensorSite.wrist, reason: slug);
      }
    });
  });

  group('detector defaults agree with the asset', () {
    test('every family fallback matches the profile thresholds', () {
      // The detector keeps a per-family fallback table for callers that drive
      // it from a bare RepMovement (fixtures, pure tests). Two sources of
      // truth is a bug waiting to happen, so this pins them together.
      final seen = <RepMovement>{};

      for (final raw in profiles) {
        final profile = RepTrackingProfile.fromJson(raw);
        final family = profile.family;
        if (family == null || !seen.add(family)) continue;

        final fallback = RepDetectorConfig.forMovement(family);
        expect(fallback.minPeriodMs, profile.minPeriodMs, reason: family.id);
        expect(fallback.maxPeriodMs, profile.maxPeriodMs, reason: family.id);

        final expectedAmplitude = profile.channels.first == RepChannel.dyn
            ? profile.minCycleAmplitudeMs2
            : profile.minCycleAmplitudeDeg;
        expect(fallback.minCycleAmplitude, expectedAmplitude, reason: family.id);
      }

      expect(
        seen,
        hasLength(RepMovement.values.length),
        reason: 'a RepMovement value no catalogue row uses — drop it or map to it',
      );
    });

    test('forProfile picks the amplitude floor matching the channel', () {
      // Comparing a tilt amplitude in degrees against a m/s² floor is the
      // exact mistake that made a slow curl count as zero.
      final bench = RepTrackingProfile.fromJson(
        profiles.firstWhere((p) => p['slug'] == 'barbell-bench-press'),
      );

      final onTilt = RepDetectorConfig.forProfile(bench, channel: RepChannel.tilt);
      final onDyn = RepDetectorConfig.forProfile(bench, channel: RepChannel.dyn);

      expect(onTilt.minCycleAmplitude, bench.minCycleAmplitudeDeg);
      expect(onDyn.minCycleAmplitude, bench.minCycleAmplitudeMs2);
      expect(onTilt.minCycleAmplitude, greaterThan(onDyn.minCycleAmplitude));
    });
  });

  group('registry', () {
    tearDown(RepProfileRegistry.resetForTest);

    test('an unloaded registry reports everything as ineligible', () {
      RepProfileRegistry.resetForTest();

      expect(RepProfileRegistry.isLoaded, isFalse);
      expect(isEligible('pull-up'), isFalse);
      expect(isEligible('barbell-bench-press'), isFalse);
      expect(movementFor('pull-up'), isNull);
      expect(sensorSiteFor('pull-up'), isNull);
    });

    test('a loaded registry resolves the whole catalogue', () {
      RepProfileRegistry.loadFromJson(
        File('assets/data/rep_tracking_profiles.json').readAsStringSync(),
      );

      expect(RepProfileRegistry.isLoaded, isTrue);
      expect(RepProfileRegistry.instance.length, catalog.length);

      expect(isEligible('barbell-bench-press'), isTrue);
      expect(movementFor('barbell-bench-press'), RepMovement.horizontalPush);
      expect(sensorSiteFor('barbell-bench-press'), SensorSite.wrist);

      expect(isEligible('pull-up'), isTrue);
      expect(sensorSiteFor('pull-up'), SensorSite.pocket);

      expect(isEligible('seated-leg-curl'), isFalse);
      expect(profileFor('seated-leg-curl')!.reason, isNotEmpty);
    });

    test('an unknown or null slug is never eligible', () {
      RepProfileRegistry.loadFromJson(
        File('assets/data/rep_tracking_profiles.json').readAsStringSync(),
      );

      expect(isEligible(null), isFalse);
      expect(isEligible('some-custom-exercise'), isFalse);
      expect(profileFor('some-custom-exercise'), isNull);
    });

    test('a malformed asset throws rather than installing a partial registry', () {
      expect(
        () => RepProfileRegistry.loadFromJson('{"not": "a list"}'),
        throwsFormatException,
      );
    });
  });
}
