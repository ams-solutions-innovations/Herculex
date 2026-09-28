import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

/// Persists and reads the maintenance-estimate history (D-11).
///
/// History only: this repository never reads or writes `nutrition_targets`.
/// A saved manual target always wins in `TargetResolver`, so the estimate is
/// only ever the fallback and there is no "current"/"manual" flag here.
/// `recent` is the API Phase 29 uses to diff history for material shifts.
class TdeeEstimatesRepository {
  TdeeEstimatesRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  static const int _maxKcal = 10000;

  /// Inserts one history row. Rejects implausible values before touching the
  /// database (T-28-23). `dateIso` is the Clock's local day; `estimatedAt` is
  /// the timestamp the estimator stamped on the result.
  Future<void> record(TdeeEstimateResult r) async {
    if (r.kcal <= 0 || r.kcal > _maxKcal) {
      throw ArgumentError.value(r.kcal, 'kcal', 'must be in (0, $_maxKcal]');
    }
    if (r.windowDays < 0) {
      throw ArgumentError.value(r.windowDays, 'windowDays', 'must be >= 0');
    }
    await _db
        .into(_db.tdeeEstimates)
        .insert(
          TdeeEstimatesCompanion.insert(
            dateIso: dateIso(_clock.now()),
            method: r.method.name,
            confidence: r.confidence.name,
            windowDays: r.windowDays,
            kcal: r.kcal,
            inputsJson: jsonEncode(r.inputs),
            estimatedAt: Value(r.estimatedAt),
            observedQualified: Value(r.observedQualified),
          ),
        );
  }

  /// Newest estimate, or null when nothing has been recorded.
  Stream<TdeeEstimateResult?> watchLatest() => _newestFirst(
    limit: 1,
  ).watch().map((rows) => rows.isEmpty ? null : _toResult(rows.first));

  Future<TdeeEstimateResult?> latest() async {
    final rows = await _newestFirst(limit: 1).get();
    return rows.isEmpty ? null : _toResult(rows.first);
  }

  /// Newest-first history for hysteresis, grace and Phase 29 diffing.
  Future<List<TdeeEstimateResult>> recent({int limit = 8}) async {
    final rows = await _newestFirst(limit: limit).get();
    return rows.map(_toResult).toList(growable: false);
  }

  SimpleSelectStatement<$TdeeEstimatesTable, TdeeEstimateData> _newestFirst({
    required int limit,
  }) {
    return _db.select(_db.tdeeEstimates)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.estimatedAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
  }

  /// Validates closed-vocabulary text and decodes the display-only inputs.
  /// A malformed (possibly remote) row can never crash a read or select an
  /// unvalidated method (T-28-22).
  TdeeEstimateResult _toResult(TdeeEstimateData row) {
    return TdeeEstimateResult(
      kcal: row.kcal,
      method: TdeeMethod.fromName(row.method),
      confidence: TdeeConfidence.fromName(row.confidence),
      windowDays: row.windowDays,
      observedQualified: row.observedQualified,
      inputs: _decodeInputs(row.inputsJson),
      estimatedAt: row.estimatedAt,
    );
  }

  Map<String, Object?> _decodeInputs(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // Display-only data; fall through to empty.
    }
    return const {};
  }
}
