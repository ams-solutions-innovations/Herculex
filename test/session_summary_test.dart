import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(int id, String primaryMuscle) => ExerciseCatalogData(
      id: id,
      name: 'Exercise $id',
      primaryMuscle: primaryMuscle,
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'axial',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'strength',
      modality: 'barbell',
      cnsScore: 3,
      recoveryImpact: 3,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    );

WorkoutSessionData _session(int id, DateTime startedAt, DateTime? endedAt) =>
    WorkoutSessionData(id: id, startedAt: startedAt, endedAt: endedAt);

ResolvedSet _resolved({
  required int setId,
  required WorkoutSessionData session,
  required ExerciseCatalogData exercise,
  required DateTime completedAt,
  double weightKg = 100,
  int reps = 5,
}) {
  final we = WorkoutExerciseData(
    id: setId,
    sessionId: session.id,
    exerciseId: exercise.id,
    orderIndex: 0,
  );
  return ResolvedSet(
    set: SetEntryData(
      id: setId,
      workoutExerciseId: we.id,
      setIndex: 0,
      weightKg: weightKg,
      reps: reps,
      isWarmup: false,
      isCompleted: true,
      completedAt: completedAt,
      setType: 'standard',
    ),
    workoutExercise: we,
    session: session,
    exercise: exercise,
    setType: SetType.fromId('standard'),
    bands: const [],
    accessoryNames: const [],
    forearmMultiplier: 1.0,
  );
}

void main() {
  // Wednesday 18:00.
  final start = DateTime(2026, 7, 29, 18);
  final end = start.add(const Duration(minutes: 72));

  final bench = _ex(1, 'Chest');
  final squat = _ex(2, 'Quads');

  final thisSession = _session(1, start, end);
  final otherSession = _session(2, start.subtract(const Duration(days: 2)),
      start.subtract(const Duration(days: 2, hours: -1)));

  final snapshot = TrainingSnapshot(
    sets: [
      _resolved(
          setId: 1,
          session: thisSession,
          exercise: bench,
          completedAt: start.add(const Duration(minutes: 10))),
      _resolved(
          setId: 2,
          session: thisSession,
          exercise: bench,
          completedAt: start.add(const Duration(minutes: 20))),
      _resolved(
          setId: 3,
          session: thisSession,
          exercise: squat,
          weightKg: 140,
          reps: 3,
          completedAt: start.add(const Duration(minutes: 40))),
      // Belongs to a different session — must not leak into the summary.
      _resolved(
          setId: 4,
          session: otherSession,
          exercise: bench,
          completedAt: otherSession.startedAt),
    ],
    exerciseMuscles: const [],
  );

  group('SessionSummary', () {
    final s = SessionSummary.fromSnapshot(
      snapshot: snapshot,
      sessionId: 1,
      name: 'Push Day',
      startedAt: start,
      endedAt: end,
    );

    test('counts only sets from the requested session', () {
      expect(s.totalSets, 3);
      expect(s.exerciseCount, 2);
    });

    test('sums reps and effective tonnage', () {
      expect(s.totalReps, 5 + 5 + 3);
      // 100×5 + 100×5 + 140×3
      expect(s.tonnageKg, closeTo(1420, 0.001));
    });

    test('formats duration and tonnage for display', () {
      expect(s.durationLabel, '1h 12m');
      expect(s.tonnageLabel, '1.4 t');
    });

    test('falls back to the primary muscle when no mapping rows exist', () {
      expect(s.muscleGroups, containsAll(['Chest', 'Quads']));
      // Chest has two sets, so it ranks first.
      expect(s.muscleGroups.first, 'Chest');
    });

    test('an unfinished session reports zero duration, not a negative one', () {
      final open = SessionSummary.fromSnapshot(
        snapshot: snapshot,
        sessionId: 1,
        name: 'Push Day',
        startedAt: start,
        endedAt: null,
      );
      expect(open.duration, Duration.zero);
      expect(open.durationLabel, '0m');
    });

    test('sub-tonne volume is reported in kilograms', () {
      final light = SessionSummary.fromSnapshot(
        snapshot: TrainingSnapshot(
          sets: [
            _resolved(
                setId: 9,
                session: thisSession,
                exercise: bench,
                weightKg: 40,
                reps: 10,
                completedAt: start)
          ],
          exerciseMuscles: const [],
        ),
        sessionId: 1,
        name: 'Light',
        startedAt: start,
        endedAt: end,
      );
      expect(light.tonnageLabel, '400 kg');
    });
  });

  group('WeeklyMuscleVolume', () {
    test('only counts sets from the current week', () {
      // Monday of the week containing `start`.
      final v = WeeklyMuscleVolume.compute(snapshot: snapshot, asOf: end);
      expect(v.weekStart, DateTime(2026, 7, 27));
      // The other session was 2 days earlier — still Monday, so in-week.
      expect(v.totalSets, 4);
    });

    test('excludes sets from before Monday', () {
      final lastWeek = _session(3, DateTime(2026, 7, 23, 10),
          DateTime(2026, 7, 23, 11));
      final v = WeeklyMuscleVolume.compute(
        snapshot: TrainingSnapshot(
          sets: [
            ...snapshot.sets,
            _resolved(
                setId: 10,
                session: lastWeek,
                exercise: bench,
                completedAt: lastWeek.startedAt),
          ],
          exerciseMuscles: const [],
        ),
        asOf: end,
      );
      expect(v.totalSets, 4);
    });

    test('attributes tonnage per muscle, heaviest first', () {
      final v = WeeklyMuscleVolume.compute(snapshot: snapshot, asOf: end);
      expect(v.byMuscle.first.muscle, 'Chest');
      // 3 bench sets across both sessions × 100×5.
      expect(v.byMuscle.first.tonnageKg, closeTo(1500, 0.001));
    });
  });
}
