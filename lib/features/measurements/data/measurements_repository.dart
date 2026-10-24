import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:intl/intl.dart';

/// Body measurements + progress photo pointers (V2 §17). Photos themselves
/// live under the app documents directory — device-only, never synced.
class MeasurementsRepository {
  final AppDatabase _db;
  LocalProfileRepository? _profileRepo;

  MeasurementsRepository(this._db, [this._profileRepo]);

  void setProfileRepository(LocalProfileRepository profileRepo) {
    _profileRepo = profileRepo;
    syncOnStartup();
  }

  Future<void> syncOnStartup() async {
    final repo = _profileRepo;
    if (repo == null) return;
    final latestDbWeight = await latestBodyweightKg();
    final profile = repo.currentProfile;

    if (latestDbWeight != null) {
      if (profile != null && profile.weightKg != latestDbWeight) {
        await repo.save(
          profile.copyWith(weightKg: latestDbWeight),
          syncToLog: false,
        );
      }
    } else if (profile?.weightKg != null) {
      final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await logMeasurement(
        dateIso: todayIso,
        metric: 'bodyweight',
        value: profile!.weightKg!,
      );
    }
  }

  /// Built-in measurement metrics; UI may add `custom:<name>` keys.
  static const builtInMetrics = [
    'bodyweight',
    'body_fat',
    'neck',
    'chest',
    'arms_l',
    'arms_r',
    'waist',
    'hips',
    'thigh_l',
    'thigh_r',
    'calf_l',
    'calf_r',
    'back',
  ];

  Stream<List<BodyMeasurementData>> watchMetric(String metric) {
    return (_db.select(_db.bodyMeasurements)
          ..where((t) => t.metric.equals(metric) & t.deletedAt.isNull())
          // A previous version could leave more than one row for a day.
          // Keep the newest row deterministic while those histories exist.
          ..orderBy([
            (t) => OrderingTerm(expression: t.dateIso),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  /// Latest sample per metric (for the measurements overview screen).
  Stream<List<BodyMeasurementData>> watchAll() {
    return (_db.select(_db.bodyMeasurements)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.dateIso),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  /// Get the most recent value for each metric as a map (e.g. {'waist': 82.0, 'neck': 38.0}).
  Future<Map<String, double>> getLatestMeasurements() async {
    final rows =
        await (_db.select(_db.bodyMeasurements)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.dateIso),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();
    final map = <String, double>{};
    for (final r in rows) {
      map[r.metric] = r.value;
    }
    return map;
  }

  /// One active sample per metric per day — re-logging that day updates the
  /// existing row.  Keeping its sync identity is important: deleting and
  /// re-inserting could leave an old value visible on another device while
  /// its delete and replacement were being synced independently.
  Future<void> logMeasurement({
    required String dateIso,
    required String metric,
    required double value,
  }) async {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'must be a finite positive number',
      );
    }
    await _db.transaction(() async {
      final matching =
          await (_db.select(_db.bodyMeasurements)
                ..where(
                  (t) =>
                      t.dateIso.equals(dateIso) &
                      t.metric.equals(metric) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([
                  (t) =>
                      OrderingTerm(expression: t.id, mode: OrderingMode.desc),
                ]))
              .get();
      final now = DateTime.now();

      if (matching.isEmpty) {
        await _db
            .into(_db.bodyMeasurements)
            .insert(
              BodyMeasurementsCompanion.insert(
                dateIso: dateIso,
                metric: metric,
                value: value,
              ),
            );
      } else {
        // Update the newest active record and retire any historical duplicate.
        await (_db.update(
          _db.bodyMeasurements,
        )..where((t) => t.id.equals(matching.first.id))).write(
          BodyMeasurementsCompanion(value: Value(value), updatedAt: Value(now)),
        );
        for (final duplicate in matching.skip(1)) {
          await (_db.update(
            _db.bodyMeasurements,
          )..where((t) => t.id.equals(duplicate.id))).write(
            BodyMeasurementsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
    if (metric == 'bodyweight') {
      await _syncProfileWithLatestWeight();
    }
  }

  Future<void> deleteMeasurement(int id) async {
    final row = await (_db.select(
      _db.bodyMeasurements,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(
      _db.bodyMeasurements,
    )..where((t) => t.id.equals(id))).write(
      BodyMeasurementsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (row.metric == 'bodyweight') {
      await _syncProfileWithLatestWeight();
    }
  }

  /// Corrects the value while preserving the original measurement date and
  /// sync identity. This is the safe path for fixing an accidental entry.
  Future<void> updateMeasurement({
    required int id,
    required double value,
  }) async {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'must be a finite positive number',
      );
    }
    final row = await (_db.select(
      _db.bodyMeasurements,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return;

    await (_db.update(
      _db.bodyMeasurements,
    )..where((t) => t.id.equals(id))).write(
      BodyMeasurementsCompanion(
        value: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (row.metric == 'bodyweight') {
      await _syncProfileWithLatestWeight();
    }
  }

  Future<void> _syncProfileWithLatestWeight() async {
    final repo = _profileRepo;
    if (repo == null) return;
    final latest = await latestBodyweightKg();
    final profile =
        repo.currentProfile ??
        Profile(
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.lightlyActive,
        );
    if (profile.weightKg != latest) {
      await repo.save(profile.copyWith(weightKg: latest), syncToLog: false);
    }
  }

  /// Most recent bodyweight, used to snapshot `set_entries.bodyweight_kg`
  /// when logging weighted-bodyweight sets (V2 §9).
  Future<double?> latestBodyweightKg() async {
    final row =
        await (_db.select(_db.bodyMeasurements)
              ..where((t) => t.metric.equals('bodyweight'))
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.dateIso,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.value;
  }

  // ── Progress photos ──────────────────────────────────────────────────────

  Stream<List<ProgressPhotoData>> watchPhotos({String? pose}) {
    final q = _db.select(_db.progressPhotos)
      ..orderBy([
        (t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc),
      ]);
    if (pose != null) q.where((t) => t.pose.equals(pose));
    return q.watch();
  }

  Future<List<ProgressPhotoData>> getRecentPhotos({
    int limit = 20,
    String? pose,
  }) async {
    final q = _db.select(_db.progressPhotos)
      ..orderBy([
        (t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc),
      ])
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
    return _db
        .into(_db.progressPhotos)
        .insert(
          ProgressPhotosCompanion.insert(
            dateIso: dateIso,
            pose: pose,
            filePath: filePath,
            notes: Value(notes),
          ),
        );
  }

  Future<void> deletePhoto(int id) async {
    await (_db.delete(_db.progressPhotos)..where((t) => t.id.equals(id))).go();
  }
}
