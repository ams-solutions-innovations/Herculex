import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/core/utils/clock.dart';
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

  bool permissionsGranted = true;

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    return permissionsGranted;
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
    required int? totalEnergyBurned,
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

  group('sleep', () {
    // The night under test: 23:00 → 07:00, 8h in bed, 7h actually asleep.
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 8, day, hour, minute);

    void seedStagedNight() {
      void put(HealthDataType type, DateTime from, DateTime to) {
        adapter.data[type] = [
          ...?adapter.data[type],
          _numericPoint(type: type, value: 0, from: from, to: to),
        ];
      }

      put(HealthDataType.SLEEP_SESSION, at(12, 23), at(13, 7));
      put(HealthDataType.SLEEP_AWAKE, at(12, 23), at(12, 23, 30));
      put(HealthDataType.SLEEP_LIGHT, at(12, 23, 30), at(13, 3));
      put(HealthDataType.SLEEP_DEEP, at(13, 3), at(13, 4, 30));
      put(HealthDataType.SLEEP_REM, at(13, 4, 30), at(13, 6, 30));
      put(HealthDataType.SLEEP_AWAKE, at(13, 6, 30), at(13, 7));
    }

    const allSleepTypes = [
      HealthDataType.SLEEP_SESSION,
      HealthDataType.SLEEP_IN_BED,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_AWAKE_IN_BED,
      HealthDataType.SLEEP_OUT_OF_BED,
    ];

    Future<Map<String, double>> sleepRows() async {
      final rows = await db.select(db.healthSamples).get();
      return {
        for (final r in rows)
          if (r.kind.startsWith('sleep_')) r.kind: r.value,
      };
    }

    test(
      'sleep_hours is time actually asleep, not the whole session',
      () async {
        seedStagedNight();

        final read = await service.runDailySync();

        expect(read.sleepHours.status, HealthReadStatus.available);
        expect(read.sleepHours.value, 7.0, reason: '8h in bed − 1h awake');
        final detail = read.sleepDetail!;
        expect(detail.inBedHours, 8.0);
        expect(detail.awakeMinutes, 60);
        expect(detail.lightMinutes, 210);
        expect(detail.deepMinutes, 90);
        expect(detail.remMinutes, 120);
      },
    );

    test('the detail is persisted next to sleep_hours', () async {
      seedStagedNight();

      await service.runDailySync();

      expect(await sleepRows(), {
        'sleep_hours': 7.0,
        'sleep_in_bed_hours': 8.0,
        'sleep_awake_min': 60.0,
        'sleep_light_min': 210.0,
        'sleep_deep_min': 90.0,
        'sleep_rem_min': 120.0,
        'sleep_awakenings': 0.0,
      });
    });

    test('a session with no stages still reads, without stage rows', () async {
      adapter.data[HealthDataType.SLEEP_SESSION] = [
        _numericPoint(
          type: HealthDataType.SLEEP_SESSION,
          value: 0,
          from: at(12, 23),
          to: at(13, 7),
        ),
      ];

      final read = await service.runDailySync();
      final rows = await sleepRows();

      expect(read.sleepHours.value, 8.0);
      expect(read.sleepDetail!.hasStages, isFalse);
      expect(rows['sleep_hours'], 8.0);
      expect(rows.keys, isNot(contains('sleep_deep_min')));
      expect(rows.keys, isNot(contains('sleep_rem_min')));
    });

    test('a stage figure from an earlier read does not outlive its '
        'night', () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-08-13',
              kind: 'sleep_deep_min',
              value: 75,
            ),
          );
      adapter.data[HealthDataType.SLEEP_SESSION] = [
        _numericPoint(
          type: HealthDataType.SLEEP_SESSION,
          value: 0,
          from: at(12, 23),
          to: at(13, 7),
        ),
      ];

      await service.runDailySync();

      expect((await sleepRows()).keys, isNot(contains('sleep_deep_min')));
    });

    test('platform-unsupported sleep types are skipped, not fatal', () async {
      seedStagedNight();
      // HealthKit-only on Android; the plugin throws for it.
      adapter.errors[HealthDataType.SLEEP_IN_BED] = Exception(
        'Not available on platform',
      );

      final read = await service.runDailySync();

      expect(read.sleepHours.status, HealthReadStatus.available);
      expect(read.sleepHours.value, 7.0);
    });

    test('permission denied on every sleep type is an explicit denied read '
        'and leaves the last night untouched', () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-08-13',
              kind: 'sleep_hours',
              value: 6.5,
            ),
          );
      for (final type in allSleepTypes) {
        adapter.errors[type] = Exception('permission denied');
      }

      final read = await service.runDailySync();

      expect(read.sleepHours.status, HealthReadStatus.denied);
      expect(read.sleepDetail, isNull);
      expect((await sleepRows())['sleep_hours'], 6.5);
    });

    test('no sleep at all clears a stale night and its detail', () async {
      for (final kind in ['sleep_hours', 'sleep_in_bed_hours']) {
        await db
            .into(db.healthSamples)
            .insert(
              HealthSamplesCompanion.insert(
                dateIso: '2026-08-13',
                kind: kind,
                value: 7,
              ),
            );
      }

      final read = await service.runDailySync();

      expect(read.sleepHours.status, HealthReadStatus.empty);
      expect(await sleepRows(), isEmpty);
    });

    group('refreshSleepIfStale', () {
      test('stores last night without a full sync', () async {
        seedStagedNight();

        await service.refreshSleepIfStale();

        final rows = await sleepRows();
        expect(rows['sleep_hours'], 7.0);
        expect(rows['sleep_deep_min'], 90.0);
        // Nothing but sleep was written.
        final all = await db.select(db.healthSamples).get();
        expect(all.every((r) => r.kind.startsWith('sleep_')), isTrue);
      });

      test('reads at most once per gap', () async {
        seedStagedNight();
        await service.refreshSleepIfStale();

        // The watch syncs more data, but the clock has not moved.
        adapter.data[HealthDataType.SLEEP_SESSION] = [];
        adapter.data[HealthDataType.SLEEP_AWAKE] = [];
        adapter.data[HealthDataType.SLEEP_LIGHT] = [];
        adapter.data[HealthDataType.SLEEP_DEEP] = [];
        adapter.data[HealthDataType.SLEEP_REM] = [];
        await service.refreshSleepIfStale();

        expect((await sleepRows())['sleep_hours'], 7.0);
      });

      test('never prompts: without a grant it does nothing', () async {
        seedStagedNight();
        adapter.permissionsGranted = false;

        await service.refreshSleepIfStale();

        expect(await sleepRows(), isEmpty);
      });

      test('an empty read does not erase a stored night', () async {
        await db
            .into(db.healthSamples)
            .insert(
              HealthSamplesCompanion.insert(
                dateIso: '2026-08-13',
                kind: 'sleep_hours',
                value: 7.5,
              ),
            );

        await service.refreshSleepIfStale();

        expect((await sleepRows())['sleep_hours'], 7.5);
      });

      test('a failing read is swallowed', () async {
        for (final type in allSleepTypes) {
          adapter.errors[type] = StateError('boom');
        }

        await expectLater(service.refreshSleepIfStale(), completes);
      });
    });

    test('watchLatestSleep serves the latest stored night', () async {
      seedStagedNight();
      await service.runDailySync();

      final night = await service.watchLatestSleep().first;

      expect(night!.asleepHours, 7.0);
      expect(night.deepMinutes, 90);
    });

    test('watchLatestSleep ignores a night older than yesterday', () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-08-10',
              kind: 'sleep_hours',
              value: 8,
            ),
          );

      expect(await service.watchLatestSleep().first, isNull);
    });
  });

  test('empty step history does not return a 10000-step baseline', () async {
    final read = await service.getAverageSteps(30);

    expect(read.status, HealthReadStatus.empty);
    expect(read.value, isNull);
  });

  test(
    'writeWorkoutToHealth sends custom title, calories, and times',
    () async {
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
    },
  );

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
