import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/rep_features.dart';
import 'package:herculex/features/reps/domain/rpe_estimator.dart';

/// A row with all five features non-null, meanPeriodMs carrying whatever
/// signal a case needs and the other four held constant. Constant features
/// standardise to zero (their column carries no variance), so this
/// decouples the fit down to a single effective feature — the reduction
/// [_handComputedLooMae] below relies on to hand-verify Task 1's own
/// implementation via an independently written closed-form derivation.
RepFeatures _row(double meanPeriodMs) => RepFeatures(
      meanPeriodMs: meanPeriodMs,
      periodCv: 0.1,
      normalisedAmplitude: 1.0,
      finalRepPeriodRatio: 1.0,
      amplitudeDecayRatio: 1.0,
    );

void main() {
  group('RpeEstimator.gatePasses', () {
    test('false when sampleCount is below 10, other two conditions passing',
        () {
      expect(
        RpeEstimator.gatePasses(
          sampleCount: 9,
          distinctSessionCount: 3,
          looMae: 0.5,
        ),
        isFalse,
      );
    });

    test(
        'false when distinctSessionCount is below 3, other two conditions '
        'passing', () {
      expect(
        RpeEstimator.gatePasses(
          sampleCount: 10,
          distinctSessionCount: 2,
          looMae: 0.5,
        ),
        isFalse,
      );
    });

    test('false when looMae is above 1.0, other two conditions passing', () {
      expect(
        RpeEstimator.gatePasses(
          sampleCount: 10,
          distinctSessionCount: 3,
          looMae: 1.01,
        ),
        isFalse,
      );
    });

    test('false when looMae is null, other two conditions passing', () {
      expect(
        RpeEstimator.gatePasses(
          sampleCount: 10,
          distinctSessionCount: 3,
          looMae: null,
        ),
        isFalse,
      );
    });

    test('true when all three conditions pass', () {
      expect(
        RpeEstimator.gatePasses(
          sampleCount: 10,
          distinctSessionCount: 3,
          looMae: 1.0,
        ),
        isTrue,
      );
    });
  });

  group('RpeEstimator.estimate — gate failure', () {
    // A cleanly linear dataset (meanPeriodMs against RPE) that fits well —
    // used across these cases so the *only* thing varying is which gate
    // condition is deliberately starved.
    final wellFittingRows = [
      RpeTrainingRow(features: _row(1000), rpe: 6),
      RpeTrainingRow(features: _row(1200), rpe: 7),
      RpeTrainingRow(features: _row(1400), rpe: 8),
    ];

    test('null when sampleCount is below 10', () {
      final estimator = RpeEstimator.fit(
        rows: wellFittingRows,
        sampleCount: 5,
        distinctSessionCount: 5,
      );
      expect(estimator.estimate(_row(1200)), isNull);
    });

    test('null when distinctSessionCount is below 3', () {
      final estimator = RpeEstimator.fit(
        rows: wellFittingRows,
        sampleCount: 10,
        distinctSessionCount: 2,
      );
      expect(estimator.estimate(_row(1200)), isNull);
    });

    test('null when the fitted model'
        "'"
        's own leave-one-out error is above 1.0', () {
      // Same x values, labels with no linear relationship to them — each
      // LOO fold's own linear extrapolation misses badly.
      final poorlyFittingRows = [
        RpeTrainingRow(features: _row(1000), rpe: 9),
        RpeTrainingRow(features: _row(1200), rpe: 5),
        RpeTrainingRow(features: _row(1400), rpe: 10),
      ];
      final estimator = RpeEstimator.fit(
        rows: poorlyFittingRows,
        sampleCount: 10,
        distinctSessionCount: 5,
      );
      expect(estimator.looMae, isNotNull);
      expect(estimator.looMae!, greaterThan(1.0));
      expect(estimator.estimate(_row(1200)), isNull);
    });

    test('null when the feature vector itself has a null feature', () {
      final estimator = RpeEstimator.fit(
        rows: wellFittingRows,
        sampleCount: 10,
        distinctSessionCount: 5,
      );
      final incomplete = RepFeatures(
        meanPeriodMs: 1200,
        periodCv: 0.1,
        normalisedAmplitude: 1.0,
        finalRepPeriodRatio: null,
        amplitudeDecayRatio: 1.0,
      );
      expect(estimator.estimate(incomplete), isNull);
    });
  });

  group('RpeEstimator.estimate — output shape', () {
    final wellFittingRows = [
      RpeTrainingRow(features: _row(1000), rpe: 6),
      RpeTrainingRow(features: _row(1200), rpe: 7),
      RpeTrainingRow(features: _row(1400), rpe: 8),
    ];
    final estimator = RpeEstimator.fit(
      rows: wellFittingRows,
      sampleCount: 10,
      distinctSessionCount: 3,
    );

    test('a wildly out-of-range feature vector still clamps to 5.0-10.0',
        () {
      final farBelow = estimator.estimate(_row(-1e9));
      final farAbove = estimator.estimate(_row(1e9));
      expect(farBelow, isNotNull);
      expect(farAbove, isNotNull);
      expect(farBelow, greaterThanOrEqualTo(5.0));
      expect(farBelow, lessThanOrEqualTo(10.0));
      expect(farAbove, greaterThanOrEqualTo(5.0));
      expect(farAbove, lessThanOrEqualTo(10.0));
    });

    test('every estimate lands exactly on a 0.5 boundary', () {
      for (final period in [800.0, 1000.0, 1100.0, 1300.0, 1600.0, -5000.0]) {
        final v = estimator.estimate(_row(period));
        expect(v, isNotNull);
        final doubled = v! * 2;
        expect(
          doubled.roundToDouble(),
          closeTo(doubled, 1e-9),
          reason: '$v is not a multiple of 0.5',
        );
      }
    });
  });

  group('RpeEstimator leave-one-out MAE — hand-computed verification', () {
    test('matches an independently hand-derived closed-form value', () {
      // Three rows, only meanPeriodMs varying (the other four features are
      // constant across all rows and therefore standardise to zero,
      // decoupling the ridge fit down to this single effective feature —
      // see `_row`'s doc comment).
      final rows = [
        RpeTrainingRow(features: _row(1000), rpe: 6),
        RpeTrainingRow(features: _row(1200), rpe: 7),
        RpeTrainingRow(features: _row(1400), rpe: 8),
      ];
      final estimator = RpeEstimator.fit(
        rows: rows,
        sampleCount: 10,
        distinctSessionCount: 3,
      );

      expect(estimator.looMae, isNotNull);
      // Hand derivation (ridge lambda = 0.1, matching the implementation's
      // fixed constant):
      //
      // For a single-feature, population-standardised column, the identity
      // sum(x_std_i^2) = n holds for any data (since sum of squared
      // deviations = n * population variance by definition, and
      // x_std = deviation / stddev). With every other feature constant
      // (contributing an all-zero column, hence coefficient 0 regardless of
      // lambda), the ridge solution on the one live feature reduces to
      // beta = sum(x_std_i * y'_i) / (n + lambda), where y' is y centred on
      // its own fold mean.
      //
      // Fold leaving out (1000, 6): train on (1200,7),(1400,8).
      //   mean_x=1300, std=100 -> x_std = -1, 1; mean_y=7.5, y' = -0.5, 0.5
      //   beta = 1.0 / 2.1 = 10/21
      //   held-out x_std = (1000-1300)/100 = -3
      //   pred = 7.5 + (10/21)*(-3) = 7.5 - 10/7 = 85/14 ~= 6.0714285714286
      //   error = |85/14 - 6| = 1/14
      //
      // Fold leaving out (1200, 7): train on (1000,6),(1400,8).
      //   mean_x=1200, std=200 -> held-out x_std = 0 -> pred = mean_y = 7
      //   error = 0
      //
      // Fold leaving out (1400, 8): train on (1000,6),(1200,7).
      //   mean_x=1100, std=100 -> x_std = -1, 1; mean_y=6.5, y' = -0.5, 0.5
      //   beta = 1.0 / 2.1 = 10/21
      //   held-out x_std = (1400-1100)/100 = 3
      //   pred = 6.5 + (10/21)*3 = 6.5 + 10/7 = 111/14 ~= 7.9285714285714
      //   error = |111/14 - 8| = 1/14
      //
      // MAE = (1/14 + 0 + 1/14) / 3 = (1/7) / 3 = 1/21
      const expectedLooMae = 1 / 21;
      expect(estimator.looMae!, closeTo(expectedLooMae, 1e-9));
    });
  });

  group('RpeEstimator.fit — degenerate inputs', () {
    test(
        'a training set where every row has a null ratio feature yields a '
        'null looMae rather than an empty-matrix crash', () {
      final rows = [
        RpeTrainingRow(
          features: RepFeatures(
            meanPeriodMs: 1000,
            periodCv: 0.1,
            normalisedAmplitude: 1.0,
            finalRepPeriodRatio: null,
            amplitudeDecayRatio: null,
          ),
          rpe: 7,
        ),
        RpeTrainingRow(
          features: RepFeatures(
            meanPeriodMs: 1200,
            periodCv: 0.1,
            normalisedAmplitude: 1.0,
            finalRepPeriodRatio: null,
            amplitudeDecayRatio: null,
          ),
          rpe: 8,
        ),
      ];

      final estimator = RpeEstimator.fit(
        rows: rows,
        sampleCount: 10,
        distinctSessionCount: 5,
      );

      expect(estimator.looMae, isNull);
      expect(estimator.estimate(_row(1000)), isNull);
    });

    test('a single usable row yields a null looMae, not a crash', () {
      final estimator = RpeEstimator.fit(
        rows: [RpeTrainingRow(features: _row(1000), rpe: 7)],
        sampleCount: 10,
        distinctSessionCount: 5,
      );
      expect(estimator.looMae, isNull);
      expect(estimator.estimate(_row(1000)), isNull);
    });
  });
}
