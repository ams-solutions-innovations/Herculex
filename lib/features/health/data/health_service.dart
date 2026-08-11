import 'package:drift/drift.dart';
import 'package:health/health.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';

class HealthService {
  final AppDatabase _db;
  final Clock _clock;
  final Health _health = Health();
  DateTime? _lastSyncTime;

  HealthService(this._db, this._clock);

  DateTime? get lastSyncTime => _lastSyncTime;

  /// Requests authorizations required for Samsung Health / Health Connect / Apple Health.
  Future<bool> requestPermissions(String platform) async {
    final types = [
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
    ];

    // Only WATER, NUTRITION, and WORKOUT are ever written by this app; everything
    // else is read-only telemetry and should not request write access.
    const readWriteTypes = {
      HealthDataType.WATER,
      HealthDataType.NUTRITION,
      HealthDataType.WORKOUT,
    };
    final permissions = types
        .map((t) => readWriteTypes.contains(t) ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ)
        .toList();

    bool hasPermissions = false;
    try {
      hasPermissions = await _health.hasPermissions(types, permissions: permissions) ?? false;
      if (!hasPermissions) {
        hasPermissions = await _health.requestAuthorization(types, permissions: permissions);
      }
    } catch (e) {
      try {
        hasPermissions = await _health.requestAuthorization(types);
      } catch (_) {
        return false;
      }
    }
    return hasPermissions;
  }

  /// Runs full sync for steps, sleep, water, food, workouts, and biometrics.
  Future<void> runDailySync() async {
    final now = _clock.now();
    final todayStr = _formatDateIso(now);
    final midnight = DateTime(now.year, now.month, now.day);

    // 1. Steps
    int? steps;
    try {
      steps = await _health.getTotalStepsInInterval(midnight, now);
    } catch (_) {}

    // 2. Active Energy Burned
    double activeKcal = 0;
    try {
      final energyData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: midnight,
        endTime: now,
      );
      for (var point in energyData) {
        final val = point.value;
        if (val is NumericHealthValue) {
          activeKcal += val.numericValue.toDouble();
        }
      }
    } catch (_) {}

    // 3. Resting HR
    double restingHr = 0;
    try {
      final hrData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.RESTING_HEART_RATE],
        startTime: midnight,
        endTime: now,
      );
      if (hrData.isNotEmpty) {
        for (var point in hrData) {
          final val = point.value;
          if (val is NumericHealthValue) {
            restingHr += val.numericValue.toDouble();
          }
        }
        restingHr /= hrData.length;
      }
    } catch (_) {}

    // 4. Sleep — use SLEEP_SESSION (HC/Android) + SLEEP_ASLEEP / DEEP / REM
    double sleepHours = 0;
    try {
      final sleepData = await _health.getHealthDataFromTypes(
        types: [
          HealthDataType.SLEEP_SESSION,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
        ],
        startTime: midnight.subtract(const Duration(hours: 14)),
        endTime: now,
      );
      final intervals = sleepData.map((p) => (p.dateFrom, p.dateTo)).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));

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
    } catch (_) {}

    // 5. Water / Hydration
    double waterMl = 0;
    try {
      final waterData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WATER],
        startTime: midnight,
        endTime: now,
      );
      for (var point in waterData) {
        final val = point.value;
        if (val is NumericHealthValue) {
          final rawVal = val.numericValue.toDouble();
          // Convert liters to ml if < 10
          waterMl += rawVal < 10 ? rawVal * 1000.0 : rawVal;
        }
      }
    } catch (_) {}

    // 6. Food & Nutrition (Calories)
    double foodKcal = 0;
    try {
      final foodData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.NUTRITION],
        startTime: midnight,
        endTime: now,
      );
      for (var point in foodData) {
        final val = point.value;
        if (val is NumericHealthValue) {
          foodKcal += val.numericValue.toDouble();
        }
      }
    } catch (_) {}

    // 7. Weight
    double weightKg = 0;
    try {
      final weightData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: now.subtract(const Duration(days: 7)),
        endTime: now,
      );
      if (weightData.isNotEmpty) {
        final lastPoint = weightData.last.value;
        if (lastPoint is NumericHealthValue) {
          weightKg = lastPoint.numericValue.toDouble();
        }
      }
    } catch (_) {}

    await _db.transaction(() async {
      await (_db.delete(_db.healthSamples)..where((t) => t.dateIso.equals(todayStr))).go();

      if (steps != null && steps > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'steps',
                value: steps.toDouble(),
              ),
            );
      }

      if (sleepHours > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'sleep_hours',
                value: sleepHours,
              ),
            );
      }

      if (activeKcal > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'active_kcal',
                value: activeKcal,
              ),
            );
      }

      if (restingHr > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'resting_hr',
                value: restingHr,
              ),
            );
      }

      if (waterMl > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'water_ml',
                value: waterMl,
              ),
            );
      }

      if (foodKcal > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'food_kcal',
                value: foodKcal,
              ),
            );
      }

      if (weightKg > 0) {
        await _db.into(_db.healthSamples).insert(
              HealthSamplesCompanion.insert(
                dateIso: todayStr,
                kind: 'weight_kg',
                value: weightKg,
              ),
            );
      }
    });

    _lastSyncTime = now;
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
    return (_db.select(_db.healthSamples)..where((t) => t.dateIso.equals(todayStr))).watch();
  }

  Future<double> getAverageSteps(int days) async {
    final cutoff = _clock.now().subtract(Duration(days: days));
    final samples = await (_db.select(_db.healthSamples)
          ..where((t) => t.kind.equals('steps') & t.dateIso.isBiggerOrEqualValue(_formatDateIso(cutoff))))
        .get();

    if (samples.isEmpty) return 10000.0; // standard baseline step count

    final sum = samples.fold<double>(0.0, (val, element) => val + element.value);
    return sum / samples.length;
  }

  /// Get workouts from Health plugin for the last [days].
  Future<List<HealthDataPoint>> getWorkouts(int days) async {
    final now = _clock.now();
    final startTime = now.subtract(Duration(days: days));
    try {
      return await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: startTime,
        endTime: now,
      );
    } catch (e) {
      return [];
    }
  }

  String _formatDateIso(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
}
