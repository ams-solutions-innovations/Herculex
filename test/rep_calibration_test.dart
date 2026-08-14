import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';
import 'package:herculex/features/reps/domain/rep_calibration.dart';
import 'package:herculex/features/reps/domain/rep_features.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late RepTrackingRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = RepTrackingRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Inserts one confirmed-set observation. [meanPeriodMs] and
  /// [amplitudeDecayRatio] are the two knobs the scenarios below vary;
  /// everything else defaults to a constant, non-null value so a scenario
  /// that only wants one feature to carry signal gets a decoupled fit (a
  /// constant feature standardises to zero, contributing nothing — the
  /// same reduction `test/rpe_estimator_test.dart` relies on).
  Future<void> insertObservation({
    required int sessionId,
    required double meanPeriodMs,
    double amplitudeDecayRatio = 1.0,
    int? confirmedRpeX10,
    int featureVersion = RepFeatures.version,
    String slug = 'pull-up',
    String source = 'wrist',
    String? placement,
    String sensorType = 'linear_acceleration',
  }) async {
    final featuresJson = jsonEncode({
      'v': featureVersion,
      'meanPeriodMs': meanPeriodMs,
      'periodCv': 0.05,
      'normalisedAmplitude': 1.0,
      'finalRepPeriodRatio': 1.0,
      'amplitudeDecayRatio': amplitudeDecayRatio,
    });
    await repo.recordObservation(
      exerciseSlug: slug,
      sessionId: sessionId,
      recordedAt: DateTime(2026, 1, 1).add(Duration(minutes: sessionId)),
      source: source,
      placement: placement,
      sensorType: sensorType,
      detectedReps: 8,
      confirmedReps: 8,
      confidence: 0.9,
      confirmedRpeX10: confirmedRpeX10,
      featuresJson: featuresJson,
    );
  }

  Future<CalibrationProfile> profileFor({
    String slug = 'pull-up',
    String source = 'wrist',
    String? placement,
    String sensorType = 'linear_acceleration',
  }) async {
    final rows = await repo.observationsFor(
      slug: slug,
      source: source,
      placement: placement,
      sensorType: sensorType,
    );
    return CalibrationProfile.fromObservations(rows);
  }

  /// A cadence value strongly and linearly correlated with RPE, spread over
  /// [count] rows and 3 distinct sessions (cycled), across a wide enough
  /// range that the LOO fit is clean.
  Future<void> insertCorrelatedCadenceSets(int count) async {
    for (var i = 0; i < count; i++) {
      final period = 1000.0 + i * 50;
      final rpe = 5.0 + i * 0.3;
      await insertObservation(
        sessionId: 1 + (i % 3),
        meanPeriodMs: period,
        confirmedRpeX10: (rpe * 10).round(),
      );
    }
  }

  group('CalibrationProfile.fromObservations', () {
    test('9 confirmed sets yields insufficient', () async {
      await insertCorrelatedCadenceSets(9);
      final profile = await profileFor();
      expect(profile.status, CalibrationStatus.insufficient);
      expect(profile.sampleCount, 9);
    });

    test(
        '10 sets across only 2 sessions yields insufficient — the session '
        'gate bites independently of count', () async {
      for (var i = 0; i < 10; i++) {
        await insertObservation(
          sessionId: 1 + (i % 2),
          meanPeriodMs: 1000.0 + i * 50,
          confirmedRpeX10: ((5.0 + i * 0.3) * 10).round(),
        );
      }
      final profile = await profileFor();
      expect(profile.sampleCount, 10);
      expect(profile.distinctSessionCount, 2);
      expect(profile.status, CalibrationStatus.insufficient);
    });

    test(
        '10 sets across 3 sessions with strongly RPE-correlated cadence '
        'yields calibrated', () async {
      await insertCorrelatedCadenceSets(10);
      final profile = await profileFor();
      expect(profile.distinctSessionCount, 3);
      expect(profile.status, CalibrationStatus.calibrated);
      expect(profile.model, isNotNull);
      expect(profile.looMae, isNotNull);
      expect(profile.looMae!, lessThanOrEqualTo(1.0));
    });

    test(
        '10 sets across 3 sessions with random, uncorrelated RPE does NOT '
        'reach calibrated — the anti-overfitting / no-assumed-slowdown '
        'check', () async {
      // meanPeriodMs still varies (so it is not simply excluded), but the
      // RPE labels are deliberately not a function of it.
      const randomRpe = [9.0, 5.0, 8.5, 6.0, 5.5, 9.5, 6.5, 8.0, 5.0, 9.0];
      for (var i = 0; i < 10; i++) {
        await insertObservation(
          sessionId: 1 + (i % 3),
          meanPeriodMs: 1000.0 + i * 50,
          confirmedRpeX10: (randomRpe[i] * 10).round(),
        );
      }
      final profile = await profileFor();
      expect(profile.distinctSessionCount, 3);
      expect(profile.sampleCount, 10);
      expect(profile.status, isNot(CalibrationStatus.calibrated));
      expect(profile.model, isNull);
    });

    test(
        'a user whose RPE correlates with amplitudeDecayRatio but not '
        'cadence still calibrates — the model is not cadence-only',
        () async {
      for (var i = 0; i < 10; i++) {
        final decay = 0.6 + i * 0.04; // 0.60 .. 0.96, strongly increasing
        final rpe = 5.0 + i * 0.35;
        await insertObservation(
          sessionId: 1 + (i % 3),
          // Constant cadence: carries no signal at all.
          meanPeriodMs: 1200.0,
          amplitudeDecayRatio: decay,
          confirmedRpeX10: (rpe * 10).round(),
        );
      }
      final profile = await profileFor();
      expect(profile.status, CalibrationStatus.calibrated);
      expect(profile.model, isNotNull);
    });

    test(
        'observations written by an older detector version are excluded, '
        'and the exclusion can push a profile back to insufficient',
        () async {
      await insertCorrelatedCadenceSets(10);
      final calibrated = await profileFor();
      expect(calibrated.status, CalibrationStatus.calibrated);

      // Two more rows from a stale detector version — dropped entirely by
      // the version filter, so they must not even reach the count.
      await insertObservation(
        sessionId: 9,
        meanPeriodMs: 1900,
        confirmedRpeX10: 90,
        featureVersion: RepFeatures.version - 1,
      );
      await insertObservation(
        sessionId: 10,
        meanPeriodMs: 1950,
        confirmedRpeX10: 92,
        featureVersion: RepFeatures.version - 1,
      );
      final stillCalibrated = await profileFor();
      expect(stillCalibrated.sampleCount, 10);
      expect(stillCalibrated.status, CalibrationStatus.calibrated);

      // Now drop the surviving row count itself below the gate by using a
      // stale version for enough of the *original* rows that fewer than 10
      // remain.
      final rows = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        sensorType: 'linear_acceleration',
      );
      final staleFeaturesJson = jsonEncode({
        'v': RepFeatures.version - 1,
        'meanPeriodMs': 1200.0,
        'periodCv': 0.05,
        'normalisedAmplitude': 1.0,
        'finalRepPeriodRatio': 1.0,
        'amplitudeDecayRatio': 1.0,
      });
      // Directly downgrade three of the original ten rows' stored feature
      // vectors to simulate a detector-version bump between recordings.
      for (final row in rows.take(3)) {
        await (db.update(
          db.repSetObservations,
        )..where((t) => t.id.equals(row.id))).write(
          RepSetObservationsCompanion(
            featuresJson: Value(staleFeaturesJson),
          ),
        );
      }

      final regressed = await profileFor();
      expect(regressed.sampleCount, lessThan(10));
      expect(regressed.status, CalibrationStatus.insufficient);
    });

    test(
        'observations with a null confirmedRpeX10 are excluded from the RPE '
        'fit but still contribute to medianCadenceMs', () async {
      await insertCorrelatedCadenceSets(10);
      final withLabels = await profileFor();
      expect(withLabels.status, CalibrationStatus.calibrated);

      // Three more sets, no RPE ever entered for them.
      await insertObservation(sessionId: 11, meanPeriodMs: 3000);
      await insertObservation(sessionId: 12, meanPeriodMs: 3100);
      await insertObservation(sessionId: 13, meanPeriodMs: 3200);

      final withUnlabelled = await profileFor();
      // The three unlabelled rows still survive the version filter and
      // still count toward sampleCount/session count and cadence stats.
      expect(withUnlabelled.sampleCount, 13);
      expect(
        withUnlabelled.medianCadenceMs,
        isNot(withLabels.medianCadenceMs),
      );
      // The RPE model itself is unaffected — still trained on the same 10
      // labelled rows, still calibrated.
      expect(withUnlabelled.status, CalibrationStatus.calibrated);
    });

    test(
        'a changed placement yields a fresh insufficient profile while the '
        'original key stays calibrated', () async {
      for (var i = 0; i < 10; i++) {
        final period = 1000.0 + i * 50;
        final rpe = 5.0 + i * 0.3;
        await insertObservation(
          sessionId: 1 + (i % 3),
          meanPeriodMs: period,
          confirmedRpeX10: (rpe * 10).round(),
          source: 'phone',
          placement: 'pocket_front',
          sensorType: 'accelerometer',
        );
      }
      final pocketProfile = await profileFor(
        source: 'phone',
        placement: 'pocket_front',
        sensorType: 'accelerometer',
      );
      expect(pocketProfile.status, CalibrationStatus.calibrated);

      final armbandProfile = await profileFor(
        source: 'phone',
        placement: 'armband',
        sensorType: 'accelerometer',
      );
      expect(armbandProfile.sampleCount, 0);
      expect(armbandProfile.status, CalibrationStatus.insufficient);

      // Re-querying the original key still returns the untouched, still
      // calibrated profile.
      final pocketAgain = await profileFor(
        source: 'phone',
        placement: 'pocket_front',
        sensorType: 'accelerometer',
      );
      expect(pocketAgain.status, CalibrationStatus.calibrated);
    });

    test('an empty observation list yields insufficient with zero counts',
        () {
      final profile = CalibrationProfile.fromObservations(const []);
      expect(profile.status, CalibrationStatus.insufficient);
      expect(profile.sampleCount, 0);
      expect(profile.distinctSessionCount, 0);
      expect(profile.model, isNull);
      expect(profile.looMae, isNull);
      expect(profile.estimate(_dummyFeatures), isNull);
    });
  });
}

final RepFeatures _dummyFeatures = RepFeatures(
  meanPeriodMs: 1200,
  periodCv: 0.05,
  normalisedAmplitude: 1.0,
  finalRepPeriodRatio: 1.0,
  amplitudeDecayRatio: 1.0,
);
