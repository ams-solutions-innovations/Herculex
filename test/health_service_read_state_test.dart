import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/data/health_adapter.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/health/domain/health_read_state.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.fixed);
  final DateTime fixed;

  @override
  DateTime now() => fixed;
}

class _FakeHealthAdapter implements HealthAdapter {
  int? steps;
  Object? stepsError;
  final data = <HealthDataType, List<HealthDataPoint>>{};
  final errors = <HealthDataType, Object>{};

  @override
  Future<void> configure() async {}

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime,
  ) async {
    final error = stepsError;
    if (error != null) throw error;
    return steps;
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    for (final type in types) {
      final error = errors[type];
      if (error != null) throw error;
    }
    return [
      for (final type in types) ...(data[type] ?? const <HealthDataPoint>[]),
    ];
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    return true;
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    return true;
  }

  @override
  Future<bool> writeHealthData({
    required num value,
    required HealthDataType type,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return true;
  }

  Map<String, dynamic>? lastWrittenWorkout;

  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  }) async {
    lastWrittenWorkout = {
      'activityType': activityType,
      'title': title,
      'start': start,
      'end': end,
      'totalEnergyBurned': totalEnergyBurned,
      'totalEnergyBurnedUnit': totalEnergyBurnedUnit,
    };
    return true;
  }
}

HealthDataPoint _numericPoint({
  required HealthDataType type,
  required double value,
  required DateTime from,
  required DateTime to,
  HealthDataUnit unit = HealthDataUnit.NO_UNIT,
}) {
  return HealthDataPoint(
    uuid: '$type-$from-$value',
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit: unit,
    dateFrom: from,
    dateTo: to,
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'fake-device',
    sourceId: 'fake-source',
    sourceName: 'Fake Health',
  );
}

void main() {
  late AppDatabase db;
  late _FakeHealthAdapter adapter;
  late HealthService service;
  final now = DateTime(2026, 8, 13, 12);

  setUp(() async {
    db = await openTestDatabase();
    adapter = _FakeHealthAdapter();
    service = HealthService(db, _FixedClock(now), health: adapter);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'empty platform data is explicit and does not insert synthetic zeros',
    () async {
      final read = await service.runDailySync();
      final rows = await db.select(db.healthSamples).get();

      expect(read.overallStatus, HealthReadStatus.empty);
      expect(read.steps.status, HealthReadStatus.empty);
      expect(rows, isEmpty);
    },
  );

  test(
    'denied step read is explicit and leaves previous trusted steps untouched',
    () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-08-13',
              kind: 'steps',
              value: 4321,
            ),
          );
      adapter.stepsError = Exception('permission denied');

      final read = await service.runDailySync();
      final rows = await db.select(db.healthSamples).get();

      expect(read.steps.status, HealthReadStatus.denied);
      expect(rows.where((row) => row.kind == 'steps').single.value, 4321);
    },
  );

  test(
    'available metrics persist while denied metrics remain explicit',
    () async {
      adapter.steps = 12000;
      adapter.errors[HealthDataType.RESTING_HEART_RATE] = Exception(
        'authorization denied',
      );

      final read = await service.runDailySync();
      final rows = await db.select(db.healthSamples).get();

      expect(read.overallStatus, HealthReadStatus.available);
      expect(read.steps.value, 12000);
      expect(read.restingHr.status, HealthReadStatus.denied);
      expect(rows.where((row) => row.kind == 'steps').single.value, 12000);
      expect(rows.where((row) => row.kind == 'resting_hr'), isEmpty);
    },
  );

  test(
    'unexpected plugin error is explicit and does not overwrite trusted data',
    () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-08-13',
              kind: 'active_kcal',
              value: 250,
            ),
          );
      adapter.errors[HealthDataType.ACTIVE_ENERGY_BURNED] = StateError('boom');

      final read = await service.runDailySync();
      final rows = await db.select(db.healthSamples).get();

      expect(read.activeKcal.status, HealthReadStatus.error);
      expect(rows.where((row) => row.kind == 'active_kcal').single.value, 250);
    },
  );

  test(
    'overlapping sleep intervals are merged instead of double-counted',
    () async {
      adapter.data[HealthDataType.SLEEP_SESSION] = [
        _numericPoint(
          type: HealthDataType.SLEEP_SESSION,
          value: 1,
          from: DateTime(2026, 8, 13, 0),
          to: DateTime(2026, 8, 13, 4),
        ),
      ];
      adapter.data[HealthDataType.SLEEP_DEEP] = [
        _numericPoint(
          type: HealthDataType.SLEEP_DEEP,
          value: 1,
          from: DateTime(2026, 8, 13, 2),
          to: DateTime(2026, 8, 13, 6),
        ),
      ];

      final read = await service.runDailySync();

      expect(read.sleepHours.status, HealthReadStatus.available);
      expect(read.sleepHours.value, 6);
    },
  );

  test('empty step history does not return a 10000-step baseline', () async {
    final read = await service.getAverageSteps(30);

    expect(read.status, HealthReadStatus.empty);
    expect(read.value, isNull);
  });

  test('writeWorkoutToHealth sends custom title, calories, and times', () async {
    final start = DateTime(2026, 8, 13, 10, 0);
    final end = DateTime(2026, 8, 13, 11, 15);

    final success = await service.writeWorkoutToHealth(
      activityName: 'Arm Day',
      startTime: start,
      endTime: end,
      totalCaloriesBurned: 480,
    );

    expect(success, isTrue);
    expect(adapter.lastWrittenWorkout, isNotNull);
    expect(adapter.lastWrittenWorkout!['title'], equals('Arm Day'));
    expect(adapter.lastWrittenWorkout!['totalEnergyBurned'], equals(480));
    expect(adapter.lastWrittenWorkout!['start'], equals(start));
    expect(adapter.lastWrittenWorkout!['end'], equals(end));
    expect(
      adapter.lastWrittenWorkout!['activityType'],
      equals(HealthWorkoutActivityType.STRENGTH_TRAINING),
    );
  });

  test(
    'multi-source step resolution picks higher watch/Samsung Health steps over lower aggregate',
    () async {
      // Simulate Health Connect returning 996 as aggregate (e.g. from phone pedometer)
      adapter.steps = 996;
      // But data points contain Samsung Health records with 1816 steps
      adapter.data[HealthDataType.STEPS] = [
        HealthDataPoint(
          uuid: 'pedometer-phone',
          value: NumericHealthValue(numericValue: 996),
          type: HealthDataType.STEPS,
          unit: HealthDataUnit.COUNT,
          dateFrom: now.subtract(const Duration(hours: 4)),
          dateTo: now,
          sourcePlatform: HealthPlatformType.googleHealthConnect,
          sourceDeviceId: 'phone',
          sourceId: 'com.google.android.apps.fitness',
          sourceName: 'Google Fit',
        ),
        HealthDataPoint(
          uuid: 'samsung-watch-steps-1',
          value: NumericHealthValue(numericValue: 1000),
          type: HealthDataType.STEPS,
          unit: HealthDataUnit.COUNT,
          dateFrom: now.subtract(const Duration(hours: 5)),
          dateTo: now.subtract(const Duration(hours: 2)),
          sourcePlatform: HealthPlatformType.googleHealthConnect,
          sourceDeviceId: 'galaxy-watch',
          sourceId: 'com.sec.android.app.shealth',
          sourceName: 'Samsung Health',
        ),
        HealthDataPoint(
          uuid: 'samsung-watch-steps-2',
          value: NumericHealthValue(numericValue: 816),
          type: HealthDataType.STEPS,
          unit: HealthDataUnit.COUNT,
          dateFrom: now.subtract(const Duration(hours: 2)),
          dateTo: now,
          sourcePlatform: HealthPlatformType.googleHealthConnect,
          sourceDeviceId: 'galaxy-watch',
          sourceId: 'com.sec.android.app.shealth',
          sourceName: 'Samsung Health',
        ),
      ];

      final read = await service.runDailySync();

      expect(read.steps.status, HealthReadStatus.available);
      expect(read.steps.value, 1816.0);
    },
  );
}
