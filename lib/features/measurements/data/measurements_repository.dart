import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

/// Body measurements + progress photo pointers (V2 §17). Photos themselves
/// live under the app documents directory — device-only, never synced.
class MeasurementsRepository {
  final AppDatabase _db;

  MeasurementsRepository(this._db);

  /// Built-in measurement metrics; UI may add `custom:<name>` keys.
  static const builtInMetrics = [
    'bodyweight', 'body_fat', 'neck', 'chest', 'arms_l', 'arms_r', 'waist', 'hips',
    'thigh_l', 'thigh_r', 'calf_l', 'calf_r', 'back',
  ];

  Stream<List<BodyMeasurementData>> watchMetric(String metric) {
    return (_db.select(_db.bodyMeasurements)
          ..where((t) => t.metric.equals(metric))
          ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]))
        .watch();
  }

  /// Latest sample per metric (for the measurements overview screen).
  Stream<List<BodyMeasurementData>> watchAll() {
    return (_db.select(_db.bodyMeasurements)
          ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]))
        .watch();
  }

  /// Get the most recent value for each metric as a map (e.g. {'waist': 82.0, 'neck': 38.0}).
  Future<Map<String, double>> getLatestMeasurements() async {
    final rows = await (_db.select(_db.bodyMeasurements)
          ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]))
        .get();
    final map = <String, double>{};
    for (final r in rows) {
      map[r.metric] = r.value;
    }
    return map;
  }

  /// One sample per metric per day — re-logging the same day overwrites.
  Future<void> logMeasurement({
    required String dateIso,
    required String metric,
    required double value,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.bodyMeasurements)
            ..where((t) => t.dateIso.equals(dateIso) & t.metric.equals(metric)))
          .go();
      await _db.into(_db.bodyMeasurements).insert(
            BodyMeasurementsCompanion.insert(
                dateIso: dateIso, metric: metric, value: value),
          );
    });
  }

  Future<void> deleteMeasurement(int id) async {
    await (_db.delete(_db.bodyMeasurements)..where((t) => t.id.equals(id)))
        .go();
  }

  /// Most recent bodyweight, used to snapshot `set_entries.bodyweight_kg`
  /// when logging weighted-bodyweight sets (V2 §9).
  Future<double?> latestBodyweightKg() async {
    final row = await (_db.select(_db.bodyMeasurements)
          ..where((t) => t.metric.equals('bodyweight'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.value;
  }

  // ── Progress photos ──────────────────────────────────────────────────────

  Stream<List<ProgressPhotoData>> watchPhotos({String? pose}) {
    final q = _db.select(_db.progressPhotos)
      ..orderBy(
          [(t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc)]);
    if (pose != null) q.where((t) => t.pose.equals(pose));
    return q.watch();
  }

  Future<List<ProgressPhotoData>> getRecentPhotos({int limit = 20, String? pose}) async {
    final q = _db.select(_db.progressPhotos)
      ..orderBy(
          [(t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc)])
      ..limit(limit);
    if (pose != null) q.where((t) => t.pose.equals(pose));
    return q.get();
  }

  Future<int> addPhoto({
    required String dateIso,
    required String pose,
    required String filePath,
    String? notes,
  }) {
    return _db.into(_db.progressPhotos).insert(ProgressPhotosCompanion.insert(
          dateIso: dateIso,
          pose: pose,
          filePath: filePath,
          notes: Value(notes),
        ));
  }

  Future<void> deletePhoto(int id) async {
    await (_db.delete(_db.progressPhotos)..where((t) => t.id.equals(id))).go();
  }
}
