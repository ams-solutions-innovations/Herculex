// Data layer repository for sleep queries, telemetry streams, and manual logging.

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';

/// Repository coordinating local database queries for sleep metrics stored in [HealthSamples].
class SleepRepository {
  final AppDatabase _db;
  final Clock _clock;

  SleepRepository(this._db, this._clock);

  /// Retrieves a [SleepRecord] for a specific calendar day in `YYYY-MM-DD` format.
  ///
  /// Returns null if no sleep data has been recorded for that date.
  Future<SleepRecord?> getSleepForDate(String dateIso) async {
    final samples = await (_db.select(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso))).get();
    return _buildRecordFromSamples(dateIso, samples);
  }

  /// Watches the current calendar day's sleep record as a live stream.
  Stream<SleepRecord?> watchTodaySleep() {
    final todayIso = _formatDateIso(_clock.now());
    return watchSleepForDate(todayIso);
  }

  /// Watches any specified calendar day's sleep record.
  Stream<SleepRecord?> watchSleepForDate(String dateIso) {
    return (_db.select(_db.healthSamples)
          ..where((t) => t.dateIso.equals(dateIso)))
        .watch()
        .map((samples) => _buildRecordFromSamples(dateIso, samples));
  }

  /// Retrieves a list of historical [SleepRecord] entries spanning the past [days] days.
  ///
  /// Sorted in descending order (most recent day first).
  Future<List<SleepRecord>> getSleepHistory(int days) async {
    final now = _clock.now();
    final cutoff = now.subtract(Duration(days: days));
    final cutoffIso = _formatDateIso(cutoff);

    final samples = await (_db.select(
      _db.healthSamples,
    )..where((t) => t.dateIso.isBiggerOrEqualValue(cutoffIso))).get();

    final byDate = <String, List<HealthSampleData>>{};
    for (final s in samples) {
      byDate.putIfAbsent(s.dateIso, () => []).add(s);
    }

    final records = <SleepRecord>[];
    for (final entry in byDate.entries) {
      final record = _buildRecordFromSamples(entry.key, entry.value);
      if (record != null) {
        records.add(record);
      }
    }

    records.sort((a, b) => b.dateIso.compareTo(a.dateIso));
    return records;
  }

  /// Persists a manual or synchronized sleep session for [dateIso].
  ///
  /// Atomically updates or inserts matching rows in [HealthSamples].
  Future<void> saveManualSleep({
    required String dateIso,
    required double totalHours,
    DateTime? bedtime,
    DateTime? wakeTime,
    double? deepHours,
    double? remHours,
    double? lightHours,
    double? awakeHours,
    double? restingHr,
  }) async {
    await _db.transaction(() async {
      await _upsertSample(dateIso, 'sleep_hours', totalHours);

      if (deepHours != null) {
        await _upsertSample(dateIso, 'sleep_deep', deepHours);
      }
      if (remHours != null) {
        await _upsertSample(dateIso, 'sleep_rem', remHours);
      }
      if (lightHours != null) {
        await _upsertSample(dateIso, 'sleep_light', lightHours);
      }
      if (awakeHours != null) {
        await _upsertSample(dateIso, 'sleep_awake', awakeHours);
      }
      if (restingHr != null) {
        await _upsertSample(dateIso, 'resting_hr', restingHr);
      }
      if (bedtime != null) {
        await _upsertSample(
          dateIso,
          'sleep_bedtime_epoch_ms',
          bedtime.millisecondsSinceEpoch.toDouble(),
        );
      }
      if (wakeTime != null) {
        await _upsertSample(
          dateIso,
          'sleep_waketime_epoch_ms',
          wakeTime.millisecondsSinceEpoch.toDouble(),
        );
      }
    });
  }

  /// Deletes all sleep-related metrics for a given [dateIso].
  Future<void> deleteSleepForDate(String dateIso) => _db.transaction(() async {
    // Remove health-derived explanations, not just the source samples.
    final start = DateTime.parse(dateIso);
    final affected =
        await (_db.select(_db.workoutSessions)..where(
              (s) =>
                  s.startedAt.isBiggerOrEqualValue(start) &
                  s.startedAt.isSmallerThanValue(
                    // Later reports may also have used this night's value
                    // in their preceding 28-day sleep baseline.
                    DateTime(start.year, start.month, start.day + 29),
                  ),
            ))
            .get();
    await (_db.delete(
      _db.workoutReports,
    )..where((r) => r.sessionId.isIn(affected.map((s) => s.id)))).go();
    const sleepKinds = [
      'sleep_hours',
      'sleep_deep',
      'sleep_rem',
      'sleep_light',
      'sleep_awake',
      'sleep_bedtime_epoch_ms',
      'sleep_waketime_epoch_ms',
    ];

    await (_db.delete(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso) & t.kind.isIn(sleepKinds))).go();
  });

  Future<void> _upsertSample(String dateIso, String kind, double value) async {
    await (_db.delete(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso) & t.kind.equals(kind))).go();

    await _db
        .into(_db.healthSamples)
        .insert(
          HealthSamplesCompanion.insert(
            dateIso: dateIso,
            kind: kind,
            value: value,
          ),
        );
  }

  SleepRecord? _buildRecordFromSamples(
    String dateIso,
    List<HealthSampleData> samples,
  ) {
    if (samples.isEmpty) {
      return null;
    }

    double? totalHours;
    double? deepHours;
    double? remHours;
    double? lightHours;
    double? awakeHours;
    double? restingHr;
    DateTime? bedtime;
    DateTime? wakeTime;

    for (final s in samples) {
      switch (s.kind) {
        case 'sleep_hours':
          totalHours = s.value;
          break;
        case 'sleep_deep':
          deepHours = s.value;
          break;
        case 'sleep_rem':
          remHours = s.value;
          break;
        case 'sleep_light':
          lightHours = s.value;
          break;
        case 'sleep_awake':
          awakeHours = s.value;
          break;
        case 'resting_hr':
          restingHr = s.value;
          break;
        case 'sleep_bedtime_epoch_ms':
          bedtime = DateTime.fromMillisecondsSinceEpoch(s.value.round());
          break;
        case 'sleep_waketime_epoch_ms':
          wakeTime = DateTime.fromMillisecondsSinceEpoch(s.value.round());
          break;
      }
    }

    // If sleep_hours is not explicitly present, attempt sum of stages
    if (totalHours == null) {
      final stageSum =
          (deepHours ?? 0.0) + (remHours ?? 0.0) + (lightHours ?? 0.0);
      if (stageSum > 0.0) {
        totalHours = stageSum;
      }
    }

    if (totalHours == null || totalHours <= 0.0) {
      return null;
    }

    return SleepRecord.fromSamples(
      dateIso: dateIso,
      totalHours: totalHours,
      bedtime: bedtime,
      wakeTime: wakeTime,
      deepHours: deepHours,
      remHours: remHours,
      lightHours: lightHours,
      awakeHours: awakeHours,
      restingHr: restingHr,
    );
  }

  static String _formatDateIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
