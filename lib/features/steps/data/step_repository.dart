// Data layer repository for step queries, telemetry streams, and manual logging.

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/steps/domain/step_record.dart';

/// Coordinates local database operations for step metrics stored in [HealthSamples].
class StepRepository {
  final AppDatabase _db;
  final Clock _clock;

  StepRepository(this._db, this._clock);

  /// Retrieves a [StepRecord] for a specific calendar day in `YYYY-MM-DD` format.
  Future<StepRecord?> getStepsForDate(String dateIso) async {
    final samples = await (_db.select(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso))).get();
    final goal = await getDailyGoal();
    return _buildRecordFromSamples(dateIso, samples, goal);
  }

  /// Watches the current calendar day's step record as a live stream.
  Stream<StepRecord?> watchTodaySteps() {
    final todayIso = _formatDateIso(_clock.now());
    return watchStepsForDate(todayIso);
  }

  /// Watches any specified calendar day's step record.
  Stream<StepRecord?> watchStepsForDate(String dateIso) {
    return (_db.select(_db.healthSamples)
          ..where((t) => t.dateIso.equals(dateIso)))
        .watch()
        .asyncMap((samples) async {
          final goal = await getDailyGoal();
          return _buildRecordFromSamples(dateIso, samples, goal);
        });
  }

  /// Retrieves historical [StepRecord] entries spanning the past [days] days.
  ///
  /// Sorted in descending order (most recent day first).
  Future<List<StepRecord>> getStepHistory(int days) async {
    final now = _clock.now();
    final cutoff = now.subtract(Duration(days: days));
    final cutoffIso = _formatDateIso(cutoff);

    final samples = await (_db.select(
      _db.healthSamples,
    )..where((t) => t.dateIso.isBiggerOrEqualValue(cutoffIso))).get();

    final goal = await getDailyGoal();

    final byDate = <String, List<HealthSampleData>>{};
    for (final s in samples) {
      byDate.putIfAbsent(s.dateIso, () => []).add(s);
    }

    final records = <StepRecord>[];
    for (final entry in byDate.entries) {
      final record = _buildRecordFromSamples(entry.key, entry.value, goal);
      if (record != null) {
        records.add(record);
      }
    }

    records.sort((a, b) => b.dateIso.compareTo(a.dateIso));
    return records;
  }

  /// Retrieves user's global daily step goal (stored with dateIso: 'global' and kind: 'steps_goal').
  Future<int> getDailyGoal() async {
    final sample =
        await (_db.select(_db.healthSamples)..where(
              (t) => t.dateIso.equals('global') & t.kind.equals('steps_goal'),
            ))
            .getSingleOrNull();

    if (sample != null && sample.value > 0) {
      return sample.value.toInt();
    }
    return 10000;
  }

  /// Persists a custom daily step goal.
  Future<void> setDailyGoal(int goal) async {
    await _upsertSample('global', 'steps_goal', goal.toDouble());
  }

  /// Persists a manual or synchronized step session for [dateIso].
  Future<void> saveManualSteps({
    required String dateIso,
    required int stepCount,
    int? goal,
    double? distanceKm,
    double? activeKcal,
    int? activeMinutes,
    Map<int, int>? hourlySteps,
  }) async {
    await _db.transaction(() async {
      await _upsertSample(dateIso, 'steps', stepCount.toDouble());

      if (goal != null && goal > 0) {
        await _upsertSample(dateIso, 'steps_goal', goal.toDouble());
      }
      if (distanceKm != null) {
        await _upsertSample(dateIso, 'steps_distance_km', distanceKm);
      }
      if (activeKcal != null) {
        await _upsertSample(dateIso, 'steps_active_kcal', activeKcal);
      }
      if (activeMinutes != null) {
        await _upsertSample(
          dateIso,
          'steps_active_min',
          activeMinutes.toDouble(),
        );
      }
      if (hourlySteps != null && hourlySteps.isNotEmpty) {
        for (final entry in hourlySteps.entries) {
          final hourPad = entry.key.toString().padLeft(2, '0');
          await _upsertSample(
            dateIso,
            'steps_hour_$hourPad',
            entry.value.toDouble(),
          );
        }
      }
    });
  }

  /// Deletes all step metrics for a given [dateIso].
  Future<void> deleteStepsForDate(String dateIso) async {
    await (_db.delete(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso) & t.kind.like('steps%'))).go();
  }

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

  StepRecord? _buildRecordFromSamples(
    String dateIso,
    List<HealthSampleData> samples,
    int defaultGoal,
  ) {
    if (samples.isEmpty) return null;

    final byKind = <String, double>{};
    final hourly = <int, int>{};

    for (final s in samples) {
      byKind[s.kind] = s.value;
      if (s.kind.startsWith('steps_hour_')) {
        final hourStr = s.kind.replaceFirst('steps_hour_', '');
        final hour = int.tryParse(hourStr);
        if (hour != null) {
          hourly[hour] = s.value.toInt();
        }
      }
    }

    final rawSteps = byKind['steps'];
    if (rawSteps == null) return null;

    final stepCount = rawSteps.toInt();
    final customGoal = byKind['steps_goal']?.toInt() ?? defaultGoal;
    final distanceKm = byKind['steps_distance_km'];
    final activeKcal = byKind['steps_active_kcal'];
    final activeMin = byKind['steps_active_min']?.toInt();

    // If no hourly data was stored, synthesize an hourly spread for visualization
    final resolvedHourly = hourly.isNotEmpty
        ? hourly
        : _synthesizeHourlySteps(stepCount);

    return StepRecord.fromStepCount(
      dateIso: dateIso,
      stepCount: stepCount,
      goal: customGoal,
      distanceKm: distanceKm,
      activeKcal: activeKcal,
      activeMinutes: activeMin,
      hourlySteps: resolvedHourly,
    );
  }

  /// Synthesizes realistic daytime step distribution curve when hourly intervals
  /// are not provided by raw health data.
  static Map<int, int> _synthesizeHourlySteps(int totalSteps) {
    if (totalSteps <= 0) return const {};

    // Relative distribution weights from hour 0 to 23
    const weights = [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // 00:00 - 05:00 (Sleep)
      0.02,
      0.06,
      0.10,
      0.08,
      0.07,
      0.08, // 06:00 - 11:00 (Morning commute/work)
      0.12, 0.09, 0.08, 0.07, 0.11, 0.12, // 12:00 - 17:00 (Lunch & Afternoon)
      0.10,
      0.07,
      0.03,
      0.01,
      0.0,
      0.0, // 18:00 - 23:00 (Evening walk/wind-down)
    ];

    final result = <int, int>{};
    for (int h = 0; h < 24; h++) {
      result[h] = (totalSteps * weights[h]).round();
    }
    return result;
  }

  static String _formatDateIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
