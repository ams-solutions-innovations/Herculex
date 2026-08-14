import 'dart:math' as math;

import 'rep_features.dart';

/// Ridge regularisation constant, fixed rather than tuned.
///
/// At n around 10 with 5 correlated features, plain OLS overfits and reports
/// a flatteringly low training error. A small fixed lambda keeps the fit
/// honest without introducing a tuning loop — there is not enough data to
/// tune one honestly, and a tuning loop would itself leak into the LOO
/// estimate this file computes.
const double _ridgeLambda = 0.1;

/// The five features, in the fixed order the model is trained and evaluated
/// on ([_featureRow], [RpeModel.predict]). This order is fixed by
/// 10-CONTEXT ("RPE suggestion gating"), not chosen here:
/// `meanPeriodMs`, `periodCv`, `normalisedAmplitude`, `finalRepPeriodRatio`,
/// `amplitudeDecayRatio`.
const int _featureCount = 5;

/// One confirmed set's feature vector paired with the user's confirmed RPE,
/// in RPE **points** (e.g. `8.0`), not `rpeX10` units.
class RpeTrainingRow {
  const RpeTrainingRow({required this.features, required this.rpe});

  final RepFeatures features;
  final double rpe;
}

/// Extracts the fixed five-feature row, or null when either ratio feature
/// (undefined below 4 reps) is null.
///
/// **Rows with any null feature are excluded from the fit, never
/// imputed** — a set under 4 reps contributes no training row rather than a
/// fabricated one.
List<double>? _featureRow(RepFeatures f) {
  final finalRepPeriodRatio = f.finalRepPeriodRatio;
  final amplitudeDecayRatio = f.amplitudeDecayRatio;
  if (finalRepPeriodRatio == null || amplitudeDecayRatio == null) {
    return null;
  }
  return [
    f.meanPeriodMs,
    f.periodCv,
    f.normalisedAmplitude,
    finalRepPeriodRatio,
    amplitudeDecayRatio,
  ];
}

/// A fitted ridge model over standardised features.
///
/// Per-feature mean/stddev are computed from the training rows and stored
/// here so [predict] standardises a new row identically to how the model
/// was trained — matching the [OneRepMax]-style pure-estimator idiom this
/// file follows (`lib/features/workouts/domain/one_rep_max.dart`).
class RpeModel {
  const RpeModel({
    required this.featureMeans,
    required this.featureStddevs,
    required this.coefficients,
    required this.intercept,
  });

  final List<double> featureMeans;
  final List<double> featureStddevs;

  /// Ridge coefficients on the *standardised* features, in the fixed
  /// five-feature order.
  final List<double> coefficients;

  /// The training rows' mean RPE (centring, not a penalised intercept term —
  /// standardised features already have mean zero, so this is equivalent to
  /// fitting an unregularised intercept).
  final double intercept;

  double predict(List<double> rawFeatures) {
    var sum = intercept;
    for (var i = 0; i < rawFeatures.length; i++) {
      final std = featureStddevs[i];
      final z = std == 0 ? 0.0 : (rawFeatures[i] - featureMeans[i]) / std;
      sum += coefficients[i] * z;
    }
    return sum;
  }
}

RpeModel _fit(List<List<double>> rows, List<double> labels) {
  final n = rows.length;
  final means = List<double>.filled(_featureCount, 0);
  final stddevs = List<double>.filled(_featureCount, 0);
  for (var j = 0; j < _featureCount; j++) {
    final col = [for (final r in rows) r[j]];
    final m = col.reduce((a, b) => a + b) / n;
    final varSum = col.fold(0.0, (s, v) => s + (v - m) * (v - m));
    means[j] = m;
    stddevs[j] = math.sqrt(varSum / n);
  }

  final yMean = labels.reduce((a, b) => a + b) / n;
  final standardised = [
    for (final r in rows)
      [
        for (var j = 0; j < _featureCount; j++)
          stddevs[j] == 0 ? 0.0 : (r[j] - means[j]) / stddevs[j],
      ],
  ];
  final centeredY = [for (final y in labels) y - yMean];

  // Solve (X^T X + lambda I) beta = X^T y' for beta.
  final xtx = List.generate(
    _featureCount,
    (_) => List<double>.filled(_featureCount, 0),
  );
  final xty = List<double>.filled(_featureCount, 0);
  for (var i = 0; i < n; i++) {
    final row = standardised[i];
    for (var a = 0; a < _featureCount; a++) {
      xty[a] += row[a] * centeredY[i];
      for (var b = 0; b < _featureCount; b++) {
        xtx[a][b] += row[a] * row[b];
      }
    }
  }
  for (var a = 0; a < _featureCount; a++) {
    xtx[a][a] += _ridgeLambda;
  }

  final beta = _solveLinearSystem(xtx, xty);
  return RpeModel(
    featureMeans: means,
    featureStddevs: stddevs,
    coefficients: beta,
    intercept: yMean,
  );
}

/// Gauss-Jordan elimination with partial pivoting, solving `a * x = b`.
///
/// A near-singular pivot column (a feature with zero variance across the
/// fold, or one perfectly collinear with another) leaves that coefficient
/// at zero rather than dividing by (near) zero — the coefficient simply
/// carries no signal, which is the correct outcome, not a crash.
List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [for (final row in a) List<double>.of(row)];
  final rhs = List<double>.of(b);

  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (pivot != col) {
      final tmpRow = m[col];
      m[col] = m[pivot];
      m[pivot] = tmpRow;
      final tmpB = rhs[col];
      rhs[col] = rhs[pivot];
      rhs[pivot] = tmpB;
    }
    final diag = m[col][col];
    if (diag.abs() < 1e-12) continue;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final factor = m[r][col] / diag;
      if (factor == 0) continue;
      for (var c = col; c < n; c++) {
        m[r][c] -= factor * m[col][c];
      }
      rhs[r] -= factor * rhs[col];
    }
  }
  return [
    for (var i = 0; i < n; i++)
      m[i][i].abs() < 1e-12 ? 0.0 : rhs[i] / m[i][i],
  ];
}

/// Leave-one-out MAE, in RPE points. Each fold **refits from scratch** on
/// the remaining n-1 rows — including recomputing that fold's own
/// standardisation statistics — so no information from the held-out row
/// (not even its contribution to the mean/stddev) leaks into its own
/// prediction.
double? _leaveOneOutMae(List<List<double>> rows, List<double> labels) {
  final n = rows.length;
  if (n < 2) return null;
  var totalError = 0.0;
  for (var i = 0; i < n; i++) {
    final trainRows = [for (var j = 0; j < n; j++) if (j != i) rows[j]];
    final trainLabels = [for (var j = 0; j < n; j++) if (j != i) labels[j]];
    final foldModel = _fit(trainRows, trainLabels);
    final predicted = foldModel.predict(rows[i]);
    totalError += (predicted - labels[i]).abs();
  }
  return totalError / n;
}

/// Per (user, exercise, source, placement, sensorType) RPE estimator:
/// ridge-regularised OLS on standardised features, gated by leave-one-out
/// cross-validated error rather than by row count alone.
///
/// This is where REP-05's real content lives — not the model, the gate. For
/// a user whose cadence carries no RPE signal the coefficients collapse
/// toward zero on their own, LOO error stays high, and [estimate] simply
/// never returns a value. That needs no special-casing anywhere in this
/// file.
class RpeEstimator {
  RpeEstimator._({
    required this.sampleCount,
    required this.distinctSessionCount,
    required this.looMae,
    RpeModel? model,
  }) : _model = model;

  /// Fits (or fails to fit, when fewer than two rows survive the null-
  /// feature filter) a ridge model over [rows] and computes its
  /// leave-one-out MAE.
  ///
  /// [sampleCount] and [distinctSessionCount] are the counts [gatePasses]
  /// is evaluated against. They are accepted as explicit parameters rather
  /// than derived from `rows.length` because a caller (`CalibrationProfile`)
  /// may key the gate on a broader "confirmed sets" population than the
  /// (possibly smaller) subset of rows this estimator can actually train
  /// on — a set with a null feature contributes no training row, but it was
  /// still a confirmed set.
  factory RpeEstimator.fit({
    required List<RpeTrainingRow> rows,
    required int sampleCount,
    required int distinctSessionCount,
  }) {
    final featureRows = <List<double>>[];
    final labels = <double>[];
    for (final row in rows) {
      final r = _featureRow(row.features);
      if (r == null) continue;
      featureRows.add(r);
      labels.add(row.rpe);
    }

    if (featureRows.length < 2) {
      return RpeEstimator._(
        sampleCount: sampleCount,
        distinctSessionCount: distinctSessionCount,
        looMae: null,
      );
    }

    final model = _fit(featureRows, labels);
    final looMae = _leaveOneOutMae(featureRows, labels);
    return RpeEstimator._(
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
      looMae: looMae,
      model: model,
    );
  }

  final int sampleCount;
  final int distinctSessionCount;

  /// Null when the fit could not run (fewer than two usable training rows).
  final double? looMae;

  final RpeModel? _model;

  /// The single named gate predicate. All three REP-05 thresholds live
  /// here and nowhere else in this file, so a future threshold change
  /// happens in exactly one place.
  static bool gatePasses({
    required int sampleCount,
    required int distinctSessionCount,
    required double? looMae,
  }) =>
      sampleCount >= 10 &&
      distinctSessionCount >= 3 &&
      looMae != null &&
      looMae <= 1.0;

  /// Null whenever the gate fails, [f] carries a null feature, or no model
  /// could be fit. Matches the `OneRepMax.estimate` idiom this file follows:
  /// a nullable return means "cannot estimate", never a sentinel value.
  ///
  /// Clamped to 5.0-10.0 and rounded to the nearest 0.5, matching how
  /// `rpeX10` is entered elsewhere in the app.
  double? estimate(RepFeatures f) {
    if (!gatePasses(
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
      looMae: looMae,
    )) {
      return null;
    }
    final model = _model;
    final row = _featureRow(f);
    if (model == null || row == null) return null;

    final raw = model.predict(row);
    final clamped = math.max(5.0, math.min(10.0, raw));
    return (clamped * 2).round() / 2;
  }
}
