import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/data/workout_energy_service.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/workout_energy_estimator.dart';

import '../../support/test_database.dart';

class _Clock implements Clock {
  final DateTime fixed;
  const _Clock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  final start = DateTime(2026, 10, 28, 10);
  final end = start.add(const Duration(hours: 1));
  final clock = _Clock(end);
  const profile = Profile(
    goal: FitnessGoal.maintenance,
    activityLevel: ActivityLevel.active,
    weightKg: 80,
    heightCm: 180,
    ageYears: 30,
    sex: BiologicalSex.male,
  );
  late AppDatabase db;
  late WorkoutEnergyService service;
  late WorkoutSessionData session;
  late int exerciseRow;

  setUp(() async {
    db = await openTestDatabase();
    service = WorkoutEnergyService(db, clock);
    final sessionId = await db
        .into(db.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: start));
    session = await (db.select(
      db.workoutSessions,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    final ex = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Back Squat',
            primaryMuscle: 'Quads',
            equipment: 'barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'axial',
            movementPattern: const Value('squat'),
          ),
        );
    exerciseRow = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: ex,
            orderIndex: 0,
          ),
        );
  });
  tearDown(() => db.close());

  Future<int> addSet({
    bool warmup = false,
    bool completed = true,
    int index = 0,
    int at = 60,
  }) => db
      .into(db.setEntries)
      .insert(
        SetEntriesCompanion.insert(
          workoutExerciseId: exerciseRow,
          setIndex: index,
          weightKg: 80,
          reps: 10,
          isCompleted: Value(completed),
          isWarmup: Value(warmup),
          completedAt: Value(start.add(Duration(seconds: at))),
        ),
      );
  Future<void> measure(
    String metric,
    double value,
    String date, {
    bool deleted = false,
  }) async {
    await db
        .into(db.bodyMeasurements)
        .insert(
          BodyMeasurementsCompanion.insert(
            dateIso: date,
            metric: metric,
            value: value,
            deletedAt: deleted ? Value(end) : const Value.absent(),
          ),
        );
  }

  test(
    'energy includes completed warmups while training analytics still excludes them',
    () async {
      await addSet(warmup: true);
      await addSet(index: 1, at: 300);
      await addSet(index: 2, at: 600, completed: false);
      final energy = await service.estimate(session: session, profile: profile);
      expect(energy.workSeconds, 60);
      final analytics = await TrainingSnapshot.load(db, sessionId: session.id);
      expect(analytics.sets.length, 1);
      final energySnapshot = await TrainingSnapshot.load(
        db,
        sessionId: session.id,
        includeWarmups: true,
      );
      expect(energySnapshot.sets.length, 2);
    },
  );

  test(
    'uses dated body mass and BF, ignoring future and deleted measurements',
    () async {
      await addSet();
      await measure('bodyweight', 70, '2026-10-27');
      await measure('body_fat', 20, '2026-10-27');
      await measure('bodyweight', 150, '2026-10-29');
      await measure('body_fat', 40, '2026-10-28', deleted: true);
      final snapshot = await TrainingSnapshot.load(
        db,
        sessionId: session.id,
        includeWarmups: true,
      );
      final expected = WorkoutEnergyEstimator.estimate(
        snapshot: snapshot,
        sessionId: session.id,
        startedAt: start,
        endedAt: end,
        profile: profile,
        userWeightKg: 70,
        bodyFatPercent: 20,
      );
      final actual = await service.estimate(session: session, profile: profile);
      expect(actual.conservativeKcal, expected.conservativeKcal);
    },
  );

  test(
    'stale body fat cannot silently personalize a current workout',
    () async {
      await addSet();
      final initial = await service.estimate(
        session: session,
        profile: profile,
      );
      await measure('body_fat', 60, '2025-01-01');
      await measure('bodyweight', 150, '2025-01-01');
      final stale = await service.estimate(session: session, profile: profile);
      expect(stale.conservativeKcal, initial.conservativeKcal);
    },
  );

  test('deleting or uncompleting a set removes its energy', () async {
    final id = await addSet();
    expect(
      (await service.estimate(session: session, profile: profile)).workKcal,
      greaterThan(0),
    );
    await (db.update(db.setEntries)..where((s) => s.id.equals(id))).write(
      SetEntriesCompanion(deletedAt: Value(end)),
    );
    expect(
      (await service.estimate(session: session, profile: profile)).activeKcal,
      0,
    );
  });

  test(
    'direct and watch finish routes persist a conservative estimate too',
    () async {
      await addSet();
      await measure('bodyweight', 80, '2026-10-28');
      final expected = await service.estimate(session: session);
      final repo = WorkoutsRepository(db, clock);
      await repo.endSession(session.id);
      final saved = await (db.select(
        db.workoutSessions,
      )..where((s) => s.id.equals(session.id))).getSingle();
      expect(saved.caloriesBurned, expected.activeKcal);
      expect(saved.caloriesBurned!, lessThan(20));
      expect(saved.endedAt, end);
      await repo.endSession(
        session.id,
        endedAt: end.add(const Duration(hours: 2)),
      );
      final edited = await (db.select(
        db.workoutSessions,
      )..where((s) => s.id.equals(session.id))).getSingle();
      expect(edited.caloriesBurned, saved.caloriesBurned);
    },
  );

  test('a completed empty session stores zero', () async {
    await WorkoutsRepository(db, clock).endSession(session.id);
    final saved = await (db.select(
      db.workoutSessions,
    )..where((s) => s.id.equals(session.id))).getSingle();
    expect(saved.caloriesBurned, 0);
  });
}
