import 'package:drift/drift.dart';
import 'package:health/health.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';
import '../domain/health_read_state.dart';
import 'health_adapter.dart';

class HealthService {
  final AppDatabase _db;
  final Clock _clock;
  final HealthAdapter _health;
  DateTime? _lastSyncTime;
  DailyHealthRead? _lastDailyRead;

  HealthService(this._db, this._clock, {HealthAdapter? health})
    : _health = health ?? PluginHealthAdapter();

  DateTime? get lastSyncTime => _lastSyncTime;
  DailyHealthRead? get lastDailyRead => _lastDailyRead;

  static const List<HealthDataType> _syncTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.WATER,
    HealthDataType.NUTRITION,
    HealthDataType.WEIGHT,
    HealthDataType.WORKOUT,
    HealthDataType.MENSTRUATION_FLOW,
  ];

  // Only WATER, NUTRITION, and WORKOUT are ever written by this app; everything
  // else is read-only telemetry and should not request write access.
  static const Set<HealthDataType> _readWriteTypes = {
    HealthDataType.WATER,
    HealthDataType.NUTRITION,
    HealthDataType.WORKOUT,
  };

  static List<HealthDataAccess> get _syncPermissions => _syncTypes
      .map(
        (t) => _readWriteTypes.contains(t)
            ? HealthDataAccess.READ_WRITE
            : HealthDataAccess.READ,
      )
      .toList();

  /// Checks whether authorization has already been granted, without
  /// prompting. Used to reconcile UI "connected" state with the real OS
  /// grant on app start, since that state is never persisted locally.
  Future<bool> checkHasPermissions() async {
    await _health.configure();
    try {
      return await _health.hasPermissions(
            _syncTypes,
            permissions: _syncPermissions,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Requests authorizations required for Samsung Health / Health Connect / Apple Health.
  Future<bool> requestPermissions(String platform) async {
    await _health.configure();
    final types = _syncTypes;
    final permissions = _syncPermissions;

    bool hasPermissions = false;
    try {
      hasPermissions =
          await _health.hasPermissions(types, permissions: permissions) ??
          false;
      if (!hasPermissions) {
        hasPermissions = await _health.requestAuthorization(
          types,
          permissions: permissions,
        );
      }
    } catch (_) {
      try {
        hasPermissions = await _health.requestAuthorization(types);
      } catch (_) {
        return false;
      }
    }
    return hasPermissions;
  }

  /// Runs full sync for steps, sleep, water, food, workouts, and biometrics.
  Future<DailyHealthRead> runDailySync() async {
    await _health.configure();
    final now = _clock.now();
    final todayStr = _formatDateIso(now);
    final midnight = DateTime(now.year, now.month, now.day);

    final result = DailyHealthRead(
      dateIso: todayStr,
      steps: await _readSteps(midnight, now),
      activeKcal: await _readSummedNumeric(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: midnight,
        endTime: now,
      ),
      restingHr: await _readAverageNumeric(
        types: [HealthDataType.RESTING_HEART_RATE],
        startTime: midnight,
        endTime: now,
      ),
      sleepHours: await _readSleepHours(midnight, now),
      waterMl: await _readWaterMl(midnight, now),
      foodKcal: await _readSummedNumeric(
        types: [HealthDataType.NUTRITION],
        startTime: midnight,
        endTime: now,
      ),
      weightKg: await _readLatestNumeric(
        types: [HealthDataType.WEIGHT],
        startTime: now.subtract(const Duration(days: 7)),
        endTime: now,
      ),
      readAt: now,
    );

    await _persistDailyRead(result);
    _lastSyncTime = now;
    _lastDailyRead = result;
    return result;
  }

  Future<HealthRead<List<HealthDataPoint>>> readWorkouts(int days) async {
    final now = _clock.now();
    final startTime = now.subtract(Duration(days: days));
    const types = [HealthDataType.WORKOUT];
    try {
      final data = await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: now,
      );
      if (data.isEmpty) {
        return HealthRead<List<HealthDataPoint>>.empty(
          readAt: now,
          dataTypes: _typeNames(types),
        );
      }
      return HealthRead<List<HealthDataPoint>>.available(
        value: data,
        readAt: now,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<List<HealthDataPoint>>(error, types, now);
    }
  }

  /// Writes water intake from Herculex out to Samsung Health / Health Connect.
  Future<bool> writeWaterToHealth(double volumeMl, DateTime timestamp) async {
    try {
      final liters = volumeMl / 1000.0;
      return await _health.writeHealthData(
        value: liters,
        type: HealthDataType.WATER,
        startTime: timestamp,
        endTime: timestamp,
      );
    } catch (_) {
      return false;
    }
  }

  /// Writes meal calories & macros from Herculex out to Samsung Health / Health Connect.
  Future<bool> writeMealToHealth({
    required double calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    required DateTime timestamp,
  }) async {
    try {
      return await _health.writeHealthData(
        value: calories,
        type: HealthDataType.NUTRITION,
        startTime: timestamp,
        endTime: timestamp,
      );
    } catch (_) {
      return false;
    }
  }

  /// Writes workout session from Herculex out to Samsung Health / Health Connect.
  Future<bool> writeWorkoutToHealth({
    required String activityName,
    required DateTime startTime,
    required DateTime endTime,
    required int totalCaloriesBurned,
  }) async {
    try {
      return await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.WEIGHTLIFTING,
        title: activityName,
        start: startTime,
        end: endTime,
        totalEnergyBurned: totalCaloriesBurned,
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );
    } catch (_) {
      return false;
    }
  }

  Stream<List<HealthSampleData>> watchTodaySamples() {
    final todayStr = _formatDateIso(_clock.now());
    return (_db.select(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(todayStr))).watch();
  }

  Future<HealthRead<double>> getAverageSteps(int days) async {
    final now = _clock.now();
    final cutoff = now.subtract(Duration(days: days));
    final samples =
        await (_db.select(_db.healthSamples)..where(
              (t) =>
                  t.kind.equals('steps') &
                  t.dateIso.isBiggerOrEqualValue(_formatDateIso(cutoff)),
            ))
            .get();

    if (samples.isEmpty) {
      return HealthRead<double>.empty(readAt: now, dataTypes: const ['steps']);
    }

    final sum = samples.fold<double>(
      0.0,
      (val, element) => val + element.value,
    );
    return HealthRead<double>.available(
      value: sum / samples.length,
      readAt: now,
      dataTypes: const ['steps'],
    );
  }

  Future<HealthRead<double>> _readSteps(
    DateTime startTime,
    DateTime endTime,
  ) async {
    const types = [HealthDataType.STEPS];
    try {
      final steps = await _health.getTotalStepsInInterval(startTime, endTime);
      if (steps == null) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }
      return HealthRead<double>.available(
        value: steps.toDouble(),
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<HealthRead<double>> _readSummedNumeric({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final data = await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
      final values = _numericValues(data);
      if (values.isEmpty) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }
      final sum = values.fold<double>(0.0, (value, next) => value + next);
      return HealthRead<double>.available(
        value: sum,
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<HealthRead<double>> _readAverageNumeric({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final data = await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
      final values = _numericValues(data);
      if (values.isEmpty) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }
      final sum = values.fold<double>(0.0, (value, next) => value + next);
      return HealthRead<double>.available(
        value: sum / values.length,
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<HealthRead<double>> _readLatestNumeric({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final data = await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
      final sorted = [...data]
        ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      for (final point in sorted.reversed) {
        final value = _numericValue(point);
        if (value != null) {
          return HealthRead<double>.available(
            value: value,
            readAt: endTime,
            dataTypes: _typeNames(types),
          );
        }
      }
      return HealthRead<double>.empty(
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<HealthRead<double>> _readWaterMl(
    DateTime startTime,
    DateTime endTime,
  ) async {
    const types = [HealthDataType.WATER];
    try {
      final data = await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
      final values = _numericValues(data);
      if (values.isEmpty) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }
      final total = values.fold<double>(0.0, (sum, raw) {
        return sum + (raw < 10 ? raw * 1000.0 : raw);
      });
      return HealthRead<double>.available(
        value: total,
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<HealthRead<double>> _readSleepHours(
    DateTime midnight,
    DateTime endTime,
  ) async {
    const types = [
      HealthDataType.SLEEP_SESSION,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_REM,
    ];
    try {
      final sleepData = await _health.getHealthDataFromTypes(
        types: types,
        startTime: midnight.subtract(const Duration(hours: 14)),
        endTime: endTime,
      );
      final intervals =
          sleepData
              .where((p) => p.dateTo.isAfter(p.dateFrom))
              .map((p) => (p.dateFrom, p.dateTo))
              .toList()
            ..sort((a, b) => a.$1.compareTo(b.$1));

      if (intervals.isEmpty) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }

      var sleepHours = 0.0;
      DateTime? mergedStart;
      DateTime? mergedEnd;
      for (final interval in intervals) {
        final (start, end) = interval;
        if (mergedEnd == null) {
          mergedStart = start;
          mergedEnd = end;
        } else if (!start.isAfter(mergedEnd)) {
          if (end.isAfter(mergedEnd)) mergedEnd = end;
        } else {
          sleepHours += mergedEnd.difference(mergedStart!).inMinutes / 60.0;
          mergedStart = start;
          mergedEnd = end;
        }
      }
      if (mergedEnd != null) {
        sleepHours += mergedEnd.difference(mergedStart!).inMinutes / 60.0;
      }

      if (sleepHours <= 0) {
        return HealthRead<double>.empty(
          readAt: endTime,
          dataTypes: _typeNames(types),
        );
      }
      return HealthRead<double>.available(
        value: sleepHours,
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    } catch (error) {
      return _failedRead<double>(error, types, endTime);
    }
  }

  Future<void> _persistDailyRead(DailyHealthRead result) async {
    await _db.transaction(() async {
      await _applyMetricRead(result.dateIso, 'steps', result.steps);
      await _applyMetricRead(result.dateIso, 'sleep_hours', result.sleepHours);
      await _applyMetricRead(result.dateIso, 'active_kcal', result.activeKcal);
      await _applyMetricRead(result.dateIso, 'resting_hr', result.restingHr);
      await _applyMetricRead(result.dateIso, 'water_ml', result.waterMl);
      await _applyMetricRead(result.dateIso, 'food_kcal', result.foodKcal);
      await _applyMetricRead(result.dateIso, 'weight_kg', result.weightKg);
    });
  }

  Future<void> _applyMetricRead(
    String dateIso,
    String kind,
    HealthRead<double> read,
  ) async {
    if (read.status == HealthReadStatus.available && read.value != null) {
      await _deleteMetric(dateIso, kind);
      await _db
          .into(_db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: dateIso,
              kind: kind,
              value: read.value!,
            ),
          );
      return;
    }

    if (read.status == HealthReadStatus.empty) {
      await _deleteMetric(dateIso, kind);
    }
  }

  Future<void> _deleteMetric(String dateIso, String kind) {
    return (_db.delete(
      _db.healthSamples,
    )..where((t) => t.dateIso.equals(dateIso) & t.kind.equals(kind))).go();
  }

  List<double> _numericValues(List<HealthDataPoint> data) {
    return [
      for (final point in data)
        if (_numericValue(point) != null) _numericValue(point)!,
    ];
  }

  double? _numericValue(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
  }

  HealthRead<T> _failedRead<T>(
    Object error,
    List<HealthDataType> types,
    DateTime readAt,
  ) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') ||
        message.contains('authorization') ||
        message.contains('denied')) {
      return HealthRead<T>.denied(
        readAt: readAt,
        dataTypes: _typeNames(types),
        error: error,
      );
    }
    if (message.contains('unavailable') ||
        message.contains('unsupported') ||
        message.contains('not installed') ||
        message.contains('not available') ||
        message.contains('no activity')) {
      return HealthRead<T>.unavailable(
        readAt: readAt,
        dataTypes: _typeNames(types),
        error: error,
      );
    }
    return HealthRead<T>.error(
      readAt: readAt,
      dataTypes: _typeNames(types),
      error: error,
    );
  }

  List<String> _typeNames(List<HealthDataType> types) {
    return [for (final type in types) type.name];
  }

  /// Reads period / menstruation flow records from Apple Health / Health Connect.
  /// Used to sync Flo, Clue, Samsung Health, or native Health period logs into Herculex.
  Future<List<DateTime>> readPeriodDays({int lookbackDays = 60}) async {
    try {
      await _health.configure();
      final now = _clock.now();
      final startTime = now.subtract(Duration(days: lookbackDays));
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.MENSTRUATION_FLOW],
        startTime: startTime,
        endTime: now,
      );

      final days = <DateTime>{};
      for (final pt in points) {
        final start = pt.dateFrom;
        days.add(DateTime(start.year, start.month, start.day));
      }
      final sorted = days.toList()..sort((a, b) => a.compareTo(b));
      return sorted;
    } catch (_) {
      return [];
    }
  }

  String _formatDateIso(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
}
