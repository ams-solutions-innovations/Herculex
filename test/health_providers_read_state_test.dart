import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/data/health_adapter.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/health/domain/activity_adjuster.dart';
import 'package:herculex/features/health/domain/health_read_state.dart';
import 'package:herculex/features/health/presentation/health_providers.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.fixed);
  final DateTime fixed;

  @override
  DateTime now() => fixed;
}

class _EmptyHealthAdapter implements HealthAdapter {
  @override
  Future<void> configure() async {}

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime,
  ) async {
    return null;
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return const [];
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

  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  }) async {
    return true;
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final now = DateTime(2026, 8, 13, 12);

  setUp(() async {
    db = await openTestDatabase();
    final service = HealthService(
      db,
      _FixedClock(now),
      health: _EmptyHealthAdapter(),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(_FixedClock(now)),
        healthServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'activity adjustment is neutral when trusted steps are missing',
    () async {
      final result = await container.read(
        activityBasedAdjustmentProvider.future,
      );

      expect(result, ActivityAdjustmentResult.unavailable);
    },
  );

  test(
    'activity adjustment does not invent a baseline when history is empty',
    () async {
      container
          .read(lastDailyHealthReadProvider.notifier)
          .state = DailyHealthRead(
        dateIso: '2026-08-13',
        steps: HealthRead<double>.available(value: 25000, readAt: now),
        activeKcal: HealthRead<double>.empty(readAt: now),
        restingHr: HealthRead<double>.empty(readAt: now),
        sleepHours: HealthRead<double>.empty(readAt: now),
        waterMl: HealthRead<double>.empty(readAt: now),
        foodKcal: HealthRead<double>.empty(readAt: now),
        weightKg: HealthRead<double>.empty(readAt: now),
        readAt: now,
      );

      final result = await container.read(
        activityBasedAdjustmentProvider.future,
      );

      expect(result, ActivityAdjustmentResult.unavailable);
    },
  );
}
