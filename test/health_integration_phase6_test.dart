import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/data/health_adapter.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/health/domain/activity_adjuster.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';

import 'support/test_database.dart';

class _TestHealthAdapter implements HealthAdapter {
  int? steps;
  final data = <HealthDataType, List<HealthDataPoint>>{};
  bool configureCalled = false;
  bool requestAuthCalled = false;

  @override
  Future<void> configure() async {
    configureCalled = true;
  }

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime,
  ) async {
    return steps;
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final results = <HealthDataPoint>[];
    for (final type in types) {
      if (data.containsKey(type)) {
        results.addAll(data[type]!);
      }
    }
    return results;
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
    requestAuthCalled = true;
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

HealthDataPoint _makeNumericPoint(
  HealthDataType type,
  double value,
  DateTime from,
  DateTime to,
) {
  return HealthDataPoint(
    uuid: 'test-${type.name}-${from.millisecondsSinceEpoch}',
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit: HealthDataUnit.NO_UNIT,
    dateFrom: from,
    dateTo: to,
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'phone',
    sourceId: 'com.apple.Health',
    sourceName: 'Apple Health',
  );
}

void main() {
  late AppDatabase db;
  late _TestHealthAdapter adapter;
  late HealthService service;
  final now = DateTime(2026, 8, 14, 12, 0);

  setUp(() async {
    db = await openTestDatabase();
    adapter = _TestHealthAdapter();
    service = HealthService(db, SystemClock(), health: adapter);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 6 Health Integrations Sync Tests', () {
    test('runDailySync syncs steps, active calories, sleep, and resting HR into health_samples', () async {
      adapter.steps = 11500;
      adapter.data[HealthDataType.ACTIVE_ENERGY_BURNED] = [
        _makeNumericPoint(HealthDataType.ACTIVE_ENERGY_BURNED, 450, now.subtract(const Duration(hours: 3)), now.subtract(const Duration(hours: 2))),
      ];
      adapter.data[HealthDataType.RESTING_HEART_RATE] = [
        _makeNumericPoint(HealthDataType.RESTING_HEART_RATE, 58, now.subtract(const Duration(hours: 4)), now.subtract(const Duration(hours: 4))),
      ];
      adapter.data[HealthDataType.SLEEP_SESSION] = [
        _makeNumericPoint(HealthDataType.SLEEP_SESSION, 0, DateTime(2026, 8, 13, 23, 0), DateTime(2026, 8, 14, 7, 0)),
      ];

      final read = await service.runDailySync();

      expect(adapter.configureCalled, isTrue);
      expect(read.steps.value, 11500);
      expect(read.activeKcal.value, 450);
      expect(read.restingHr.value, 58);
      expect(read.sleepHours.value, 8.0);

      final samples = await db.select(db.healthSamples).get();
      expect(samples.firstWhere((s) => s.kind == 'steps').value, 11500);
      expect(samples.firstWhere((s) => s.kind == 'active_kcal').value, 450);
      expect(samples.firstWhere((s) => s.kind == 'resting_hr').value, 58);
      expect(samples.firstWhere((s) => s.kind == 'sleep_hours').value, 8.0);
    });

    test('requestPermissions invokes configure and requests authorization', () async {
      final granted = await service.requestPermissions('apple');
      expect(granted, isTrue);
      expect(adapter.configureCalled, isTrue);
    });
  });

  group('Phase 6 Calorie Target Adjustments', () {
    test('effectiveTargetsProvider dynamically adjusts macro targets when countBurnedCalories is enabled', () async {
      const profile = Profile(
        ageYears: 30,
        weightKg: 80,
        heightCm: 180,
        sex: BiologicalSex.male,
        activityLevel: ActivityLevel.active,
        goal: FitnessGoal.muscleGain,
        countBurnedCalories: true,
      );

      // Insert active_kcal sample for today
      await db.into(db.healthSamples).insert(
        HealthSamplesCompanion.insert(
          dateIso: '2026-08-14',
          kind: 'active_kcal',
          value: 400.0,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(SystemClock()),
          profileProvider.overrideWith((ref) => Stream.value(profile)),
          baselineTargetsProvider.overrideWithValue(const MacroTargets(kcal: 2500, proteinG: 180, carbsG: 280, fatG: 70)),
        ],
      );

      final sub = container.listen(
        effectiveTargetsProvider(DateTime(2026, 8, 14)),
        (_, _) {},
      );

      final targets = await container.read(
        effectiveTargetsProvider(DateTime(2026, 8, 14)).future,
      );
      expect(targets, isNotNull);
      // 2500 + 400 = 2900 kcal
      expect(targets!.kcal, 2900);
      // 400 * 0.25 / 4 = 25g protein added (180 + 25 = 205)
      expect(targets.proteinG, 205);
      // 400 * 0.50 / 4 = 50g carbs added (280 + 50 = 330)
      expect(targets.carbsG, 330);
      // 400 * 0.25 / 9 = ~11g fat added (70 + 11 = 81)
      expect(targets.fatG, 81);

      sub.close();
    });
  });

  group('Phase 6 Smart Workout Volume Adjustments', () {
    test('ActivityBasedAdjuster scales down volume for high steps and low sleep', () {
      // High activity 18k+
      final highActivity = ActivityBasedAdjuster.suggest(
        todaySteps: 19500,
        baselineSteps: 10000,
      );
      expect(highActivity.volumeFactor, 0.8);
      expect(highActivity.statusLabel, contains('VOLUME REDUCED 20%'));

      // Exhausting activity 25k+
      final restDay = ActivityBasedAdjuster.suggest(
        todaySteps: 26000,
        baselineSteps: 10000,
      );
      expect(restDay.volumeFactor, 0.0);
      expect(restDay.statusLabel, contains('REST RECOMMENDED'));

      // Normal steps but severe sleep deficit (<5h)
      final sleepDeficit = ActivityBasedAdjuster.suggest(
        todaySteps: 8000,
        baselineSteps: 10000,
        sleepHours: 4.5,
      );
      expect(sleepDeficit.volumeFactor, 0.8);
      expect(sleepDeficit.statusLabel, contains('SLEEP DEFICIT'));

      // Optimal steps and sleep
      final optimal = ActivityBasedAdjuster.suggest(
        todaySteps: 9000,
        baselineSteps: 10000,
        sleepHours: 7.5,
      );
      expect(optimal.volumeFactor, 1.0);
      expect(optimal.statusLabel, 'NO CHANGE');
    });

    test('TemplatesRepository.startSessionFromTemplate scales working sets by volumeFactor', () async {
      final repo = TemplatesRepository(db);

      // Create an exercise in ExerciseCatalog
      final exId = await db.into(db.exerciseCatalog).insert(
        ExerciseCatalogCompanion.insert(
          name: 'Barbell Bench Press',
          primaryMuscle: 'chest',
          equipment: 'barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'horizontal',
        ),
      );

      // Create a template
      final template = await repo.createTemplate(name: 'Chest & Triceps');
      final teId = await db.into(db.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          templateId: template.id,
          exerciseId: exId,
          orderIndex: 0,
          targetSets: const Value(5),
        ),
      );

      // Insert 1 warmup and 4 working sets
      await db.into(db.templateSets).insert(
        TemplateSetsCompanion.insert(
          templateExerciseId: teId,
          setOrder: 1,
          isWarmup: const Value(true),
          targetReps: const Value(12),
          targetWeightKg: const Value(40.0),
        ),
      );
      for (var i = 2; i <= 5; i++) {
        await db.into(db.templateSets).insert(
          TemplateSetsCompanion.insert(
            templateExerciseId: teId,
            setOrder: i,
            isWarmup: const Value(false),
            targetReps: const Value(8),
            targetWeightKg: const Value(80.0),
          ),
        );
      }

      // Start session with volumeFactor = 0.75 (4 working sets * 0.75 = 3 working sets)
      final sessionId = await repo.startSessionFromTemplate(
        template.id,
        volumeFactor: 0.75,
      );

      final sessionExercises = await (db.select(db.workoutExercises)..where((t) => t.sessionId.equals(sessionId))).get();
      expect(sessionExercises.length, 1);

      final sets = await (db.select(db.setEntries)..where((t) => t.workoutExerciseId.equals(sessionExercises.first.id))).get();
      // 1 warmup + 3 working sets = 4 sets total
      expect(sets.length, 4);
      expect(sets.where((s) => s.isWarmup).length, 1);
      expect(sets.where((s) => !s.isWarmup).length, 3);
    });
  });
}
