import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/data/health_adapter.dart';
import 'package:herculex/features/health/data/health_service.dart';

import 'support/test_database.dart';

class _HealthWriter implements HealthAdapter {
  int calls = 0;
  @override
  Future<void> configure() async {}
  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  }) async {
    calls++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _HealthWriter writer;
  late HealthService health;
  final start = DateTime(2026, 10, 21, 9);
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    db = await openTestDatabase();
    writer = _HealthWriter();
    health = HealthService(db, const SystemClock(), health: writer);
    await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            startedAt: start,
            sessionUuid: const Value('health-session'),
          ),
        );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await db.close();
  });
  Future<bool> export() => health.writeWorkoutToHealth(
    activityName: 'Training',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    totalCaloriesBurned: 200,
  );

  test('phone does not export a workout reserved by Apple Watch', () async {
    await db.customStatement(
      'INSERT INTO watch_health_exports VALUES (?, ?, ?, ?)',
      ['health-session', 'watch', 'pending', null],
    );
    expect(await export(), isFalse);
    expect(writer.calls, 0);
    await db.customStatement(
      "UPDATE watch_health_exports SET status = 'saved', healthkit_uuid = 'uuid'",
    );
    expect(await export(), isTrue);
    expect(writer.calls, 0);
  });
  test(
    'repeated phone finish and manual export share the same saved receipt',
    () async {
      expect(await export(), isTrue);
      expect(await export(), isTrue);
      expect(writer.calls, 1);
      final receipt = await db
          .customSelect('SELECT * FROM watch_health_exports')
          .getSingle();
      expect(receipt.data['owner'], 'phone');
      expect(receipt.data['status'], 'saved');
    },
  );

  test(
    'concurrent finish and manual export share a single HealthKit write',
    () async {
      expect(
        await Future.wait([export(), export(), export()]),
        everyElement(isTrue),
      );
      expect(writer.calls, 1);
    },
  );
}
