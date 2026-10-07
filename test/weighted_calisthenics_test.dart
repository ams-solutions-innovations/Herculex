import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_metric_format.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/sheets/equipment_variant_sheet.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late WorkoutsRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = WorkoutsRepository(db, const SystemClock());
  });

  tearDown(() async => db.close());

  group('Weighted Calisthenics Equipment Variants', () {
    test(
      'rep-based bodyweight exercise with supportsWeightedBodyweight offers bodyweight, weighted, and band',
      () {
        final dip = ExerciseCatalogData(
          id: 1,
          name: 'Dip',
          primaryMuscle: 'Chest',
          equipment: 'Bodyweight',
          mechanics: 'compound',
          force: 'push',
          plane: 'vertical',
          defaultRestSeconds: 120,
          isCustom: false,
          category: 'calisthenics',
          modality: 'bodyweight',
          cnsScore: 4,
          recoveryImpact: 2,
          loggingMetric: 'reps',
          supportsWeightedBodyweight: true,
          isReviewed: true,
        );

        final options = EquipmentVariantSheet.optionsFor(dip);
        expect(options, equals(['bodyweight', 'weighted', 'band']));
      },
    );

    test(
      'rep-based bodyweight exercise without supportsWeightedBodyweight offers only bodyweight and band',
      () {
        final plank = ExerciseCatalogData(
          id: 2,
          name: 'Sit-Up',
          primaryMuscle: 'Abs',
          equipment: 'Bodyweight',
          mechanics: 'isolation',
          force: 'pull',
          plane: 'sagittal',
          defaultRestSeconds: 60,
          isCustom: false,
          category: 'calisthenics',
          modality: 'bodyweight',
          cnsScore: 2,
          recoveryImpact: 1,
          loggingMetric: 'reps',
          supportsWeightedBodyweight: false,
          isReviewed: true,
        );

        final options = EquipmentVariantSheet.optionsFor(plank);
        expect(options, equals(['bodyweight', 'band']));
      },
    );

    test('timed bodyweight exercise offers only bodyweight', () {
      final plank = ExerciseCatalogData(
        id: 3,
        name: 'Plank',
        primaryMuscle: 'Abs',
        equipment: 'Bodyweight',
        mechanics: 'isometric',
        force: 'push',
        plane: 'sagittal',
        defaultRestSeconds: 60,
        isCustom: false,
        category: 'core',
        modality: 'bodyweight',
        cnsScore: 2,
        recoveryImpact: 1,
        loggingMetric: 'time',
        supportsWeightedBodyweight: false,
        isReviewed: true,
      );

      final options = EquipmentVariantSheet.optionsFor(plank);
      expect(options, equals(['bodyweight']));
    });
  });

  group('Effective Logging Metric', () {
    final pullUp = ExerciseCatalogData(
      id: 10,
      name: 'Pull-Up',
      primaryMuscle: 'Back',
      equipment: 'Bodyweight',
      mechanics: 'compound',
      force: 'pull',
      plane: 'vertical',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'calisthenics',
      modality: 'bodyweight',
      cnsScore: 4,
      recoveryImpact: 2,
      loggingMetric: 'reps',
      supportsWeightedBodyweight: true,
      isReviewed: true,
    );

    test('weighted variant switches metric to weightReps', () {
      expect(
        effectiveLoggingMetric(exercise: pullUp, equipmentVariant: 'weighted'),
        equals(LoggingMetric.weightReps),
      );
    });

    test('bodyweight variant keeps metric as reps', () {
      expect(
        effectiveLoggingMetric(
          exercise: pullUp,
          equipmentVariant: 'bodyweight',
        ),
        equals(LoggingMetric.reps),
      );
    });

    test('band variant keeps metric as reps', () {
      expect(
        effectiveLoggingMetric(exercise: pullUp, equipmentVariant: 'band'),
        equals(LoggingMetric.reps),
      );
    });
  });

  group('Set Formatting (SetMetricFormat.summariseSet)', () {
    const weightFmt = WeightFormat(MeasurementUnit.metric);
    const distFmt = DistanceFormat(MeasurementUnit.metric);

    test(
      'formats weighted set with +load when isWeightedBodyweight is true',
      () {
        const set = SetEntryData(
          id: 1,
          workoutExerciseId: 1,
          setIndex: 1,
          weightKg: 20.0,
          reps: 8,
          isWarmup: false,
          isCompleted: true,
          setType: 'standard',
        );

        final summary = SetMetricFormat.summariseSet(
          set,
          metric: LoggingMetric.weightReps,
          weight: weightFmt,
          distance: distFmt,
          isWeightedBodyweight: true,
        );
        expect(summary, equals('+20 kg × 8'));
      },
    );

    test(
      'formats 0kg weighted set as BW when isWeightedBodyweight is true',
      () {
        const set = SetEntryData(
          id: 2,
          workoutExerciseId: 1,
          setIndex: 1,
          weightKg: 0.0,
          reps: 10,
          isWarmup: false,
          isCompleted: true,
          setType: 'standard',
        );

        final summary = SetMetricFormat.summariseSet(
          set,
          metric: LoggingMetric.weightReps,
          weight: weightFmt,
          distance: distFmt,
          isWeightedBodyweight: true,
        );
        expect(summary, equals('BW × 10'));
      },
    );

    test('formats plain reps metric without weight', () {
      const set = SetEntryData(
        id: 3,
        workoutExerciseId: 1,
        setIndex: 1,
        weightKg: 0.0,
        reps: 12,
        isWarmup: false,
        isCompleted: true,
        setType: 'standard',
      );

      final summary = SetMetricFormat.summariseSet(
        set,
        metric: LoggingMetric.reps,
        weight: weightFmt,
        distance: distFmt,
      );
      expect(summary, equals('12 reps'));
    });
  });

  group('ResolvedSet load, tonnage and CNS score', () {
    final now = DateTime.now();
    final session = WorkoutSessionData(id: 1, startedAt: now);
    final dip = ExerciseCatalogData(
      id: 20,
      name: 'Dip',
      primaryMuscle: 'Chest',
      equipment: 'Bodyweight',
      mechanics: 'compound',
      force: 'push',
      plane: 'vertical',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'calisthenics',
      modality: 'bodyweight',
      cnsScore: 4,
      recoveryImpact: 2,
      loggingMetric: 'reps',
      supportsWeightedBodyweight: true,
      isReviewed: true,
    );

    test(
      'weighted set includes bodyweight and added weight in effective load and raises CNS score',
      () {
        const we = WorkoutExerciseData(
          id: 1,
          sessionId: 1,
          exerciseId: 20,
          orderIndex: 0,
          equipmentVariant: 'weighted',
        );
        const set = SetEntryData(
          id: 1,
          workoutExerciseId: 1,
          setIndex: 1,
          weightKg: 20.0,
          reps: 8,
          bodyweightKg: 80.0,
          isWarmup: false,
          isCompleted: true,
          setType: 'standard',
        );

        final resolved = ResolvedSet(
          session: session,
          workoutExercise: we,
          exercise: dip,
          set: set,
          setType: SetType.standard,
          bands: const [],
          accessoryNames: const [],
          forearmMultiplier: 1.0,
        );

        // Effective load = 20kg added + 80kg bodyweight = 100kg
        expect(resolved.effectiveKg, equals(100.0));
        // Tonnage = 100kg * 8 reps = 800kg
        expect(resolved.tonnageKg, equals(800.0));
        // CNS score +2 for weighted bodyweight with weightKg > 0
        expect(resolved.cnsScore, equals(6));
        expect(resolved.metric, equals(LoggingMetric.weightReps));
      },
    );

    test('pure bodyweight set includes bodyweight and base CNS score', () {
      const we = WorkoutExerciseData(
        id: 2,
        sessionId: 1,
        exerciseId: 20,
        orderIndex: 0,
        equipmentVariant: 'bodyweight',
      );
      const set = SetEntryData(
        id: 2,
        workoutExerciseId: 2,
        setIndex: 1,
        weightKg: 0.0,
        reps: 10,
        bodyweightKg: 80.0,
        isWarmup: false,
        isCompleted: true,
        setType: 'standard',
      );

      final resolved = ResolvedSet(
        session: session,
        workoutExercise: we,
        exercise: dip,
        set: set,
        setType: SetType.standard,
        bands: const [],
        accessoryNames: const [],
        forearmMultiplier: 1.0,
      );

      // Effective load = 0kg added + 80kg bodyweight = 80kg
      expect(resolved.effectiveKg, equals(80.0));
      // Tonnage = 80kg * 10 reps = 800kg
      expect(resolved.tonnageKg, equals(800.0));
      // Base CNS score = 4 (no added weight)
      expect(resolved.cnsScore, equals(4));
      expect(resolved.metric, equals(LoggingMetric.reps));
    });
  });

  group('WorkoutsRepository bodyweight snapshot on session start', () {
    test(
      'addExerciseToSession snapshots latest bodyweight for weighted-bodyweight exercise',
      () async {
        // Record a bodyweight measurement
        await db
            .into(db.bodyMeasurements)
            .insert(
              BodyMeasurementsCompanion.insert(
                metric: 'bodyweight',
                value: 78.5,
                dateIso: '2026-08-19',
              ),
            );

        // Insert catalog exercise
        final exId = await db
            .into(db.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                name: 'Test Weighted Dip',
                primaryMuscle: 'Chest',
                equipment: 'Bodyweight',
                mechanics: 'compound',
                force: 'push',
                plane: 'vertical',
                modality: const Value('bodyweight'),
                loggingMetric: const Value('reps'),
                supportsWeightedBodyweight: const Value(true),
              ),
            );

        final sessId = await repo.startSession();
        final weId = await repo.addExerciseToSession(
          sessionId: sessId,
          exerciseId: exId,
          equipmentVariant: 'weighted',
        );

        final sets = await (db.select(
          db.setEntries,
        )..where((t) => t.workoutExerciseId.equals(weId))).get();
        expect(sets, isNotEmpty);
        expect(sets.first.bodyweightKg, equals(78.5));
      },
    );
  });
}
