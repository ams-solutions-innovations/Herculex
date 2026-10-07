import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/gamification/domain/achievement_evaluator.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(
  int id, {
  String name = 'Bench Press',
  String primaryMuscle = 'Chest',
}) => ExerciseCatalogData(
  id: id,
  name: name,
  primaryMuscle: primaryMuscle,
  equipment: 'Barbell',
  mechanics: 'compound',
  force: 'push',
  plane: 'horizontal',
  defaultRestSeconds: 120,
  isCustom: false,
  category: 'strength',
  modality: 'barbell',
  cnsScore: 5,
  recoveryImpact: 3,
  loggingMetric: 'weight_reps',
  supportsWeightedBodyweight: false,
  isReviewed: true,
);

WorkoutSessionData _session(int id, DateTime startedAt, {DateTime? endedAt}) =>
    WorkoutSessionData(id: id, startedAt: startedAt, endedAt: endedAt);

WorkoutExerciseData _we(int id, int exerciseId, {int sessionId = 1}) =>
    WorkoutExerciseData(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
      plannedAllowsAdvancedTechniques: false,
    );

SetEntryData _set(
  int id,
  int weId, {
  double weightKg = 100,
  int reps = 5,
  bool isCompleted = true,
}) => SetEntryData(
  id: id,
  workoutExerciseId: weId,
  setIndex: 0,
  weightKg: weightKg,
  reps: reps,
  isWarmup: false,
  isCompleted: isCompleted,
  setType: 'standard',
);

ResolvedSet _resolved({
  required SetEntryData set,
  required WorkoutExerciseData we,
  required ExerciseCatalogData ex,
  WorkoutSessionData? session,
  List<String> accessories = const [],
}) => ResolvedSet(
  set: set,
  workoutExercise: we,
  session: session ?? _session(we.sessionId, DateTime(2026, 6, 1)),
  exercise: ex,
  setType: SetType.fromId(set.setType),
  bands: const [],
  accessoryNames: accessories,
  forearmMultiplier: 1.0,
);

void main() {
  const evaluator = AchievementEvaluator();
  const weightFormat = WeightFormat(MeasurementUnit.metric);

  group('AchievementEvaluator - Completed Sets', () {
    test('detects new 1RM / Weight PR when beating historical best', () {
      final benchEx = _ex(1, name: 'Bench Press', primaryMuscle: 'Chest');
      final session1 = _session(1, DateTime(2026, 6, 1));
      final we1 = _we(1, 1, sessionId: 1);
      final set1 = _set(1, 1, weightKg: 100, reps: 5); // e1RM ≈ 114kg

      final snapshot = TrainingSnapshot(
        sets: [_resolved(set: set1, we: we1, ex: benchEx, session: session1)],
        exerciseMuscles: [
          ExerciseMuscleData(
            id: 1,
            exerciseId: 1,
            muscle: 'Chest',
            role: 'primary',
            contribution: 1.0,
          ),
        ],
      );

      // In session 2, user logs 110kg for 5 reps (e1RM ≈ 125kg)
      final notifications = evaluator.evaluateCompletedSet(
        snapshot: snapshot,
        currentSessionId: 2,
        exerciseId: 1,
        exerciseName: 'Bench Press',
        primaryMuscle: 'Chest',
        effectiveKg: 110,
        weightKg: 110,
        reps: 5,
        accessoryNames: const [],
        equipmentVariant: 'barbell',
        setType: SetType.standard,
        weightFormat: weightFormat,
      );

      expect(
        notifications.any((n) => n.type == AchievementType.weightPr),
        isTrue,
      );
      final pr = notifications.firstWhere(
        (n) => n.type == AchievementType.weightPr,
      );
      expect(pr.title, 'Bench Press');
      expect(pr.badgeText.contains('1RM PR'), isTrue);
    });

    test('detects Rep PR at specific weight', () {
      final squatEx = _ex(2, name: 'Barbell Squat', primaryMuscle: 'Quads');
      final session1 = _session(1, DateTime(2026, 6, 1));
      final we1 = _we(2, 2, sessionId: 1);
      final set1 = _set(2, 2, weightKg: 140, reps: 6);

      final snapshot = TrainingSnapshot(
        sets: [_resolved(set: set1, we: we1, ex: squatEx, session: session1)],
        exerciseMuscles: [],
      );

      // In session 2, user logs 140kg for 8 reps
      final notifications = evaluator.evaluateCompletedSet(
        snapshot: snapshot,
        currentSessionId: 2,
        exerciseId: 2,
        exerciseName: 'Barbell Squat',
        primaryMuscle: 'Quads',
        effectiveKg: 140,
        weightKg: 140,
        reps: 8,
        accessoryNames: const [],
        equipmentVariant: 'barbell',
        setType: SetType.standard,
        weightFormat: weightFormat,
      );

      expect(notifications.any((n) => n.type == AchievementType.repPr), isTrue);
      final repPr = notifications.firstWhere(
        (n) => n.type == AchievementType.repPr,
      );
      expect(repPr.valueText.contains('8 reps'), isTrue);
    });

    test('detects Raw (No Belt) PR when lifting heavier without belt', () {
      final deadliftEx = _ex(3, name: 'Deadlift', primaryMuscle: 'Back');
      final session1 = _session(1, DateTime(2026, 6, 1));
      final we1 = _we(3, 3, sessionId: 1);
      // Past set was 180kg with Belt and 150kg Raw
      final setBelt = _set(3, 3, weightKg: 180, reps: 3);
      final setRaw = _set(4, 3, weightKg: 150, reps: 3);

      final snapshot = TrainingSnapshot(
        sets: [
          _resolved(
            set: setBelt,
            we: we1,
            ex: deadliftEx,
            session: session1,
            accessories: ['Belt'],
          ),
          _resolved(
            set: setRaw,
            we: we1,
            ex: deadliftEx,
            session: session1,
            accessories: [],
          ),
        ],
        exerciseMuscles: [],
      );

      // In session 2, user lifts 165kg Raw (No Belt)
      final notifications = evaluator.evaluateCompletedSet(
        snapshot: snapshot,
        currentSessionId: 2,
        exerciseId: 3,
        exerciseName: 'Deadlift',
        primaryMuscle: 'Back',
        effectiveKg: 165,
        weightKg: 165,
        reps: 3,
        accessoryNames: const [], // Raw
        equipmentVariant: 'barbell',
        setType: SetType.standard,
        weightFormat: weightFormat,
      );

      expect(
        notifications.any((n) => n.type == AchievementType.accessoryPr),
        isTrue,
      );
      final accPr = notifications.firstWhere(
        (n) => n.type == AchievementType.accessoryPr,
      );
      expect(accPr.badgeText.contains('RAW'), isTrue);
    });

    test(
      'detects exercise tonnage PR when single-session volume surpasses historical record',
      () {
        final benchEx = _ex(1, name: 'Bench Press', primaryMuscle: 'Chest');
        final session1 = _session(1, DateTime(2026, 6, 1));
        final we1 = _we(1, 1, sessionId: 1);
        // Past session 1: 1,000kg total for bench
        final set1 = _set(1, 1, weightKg: 100, reps: 10);

        // Current session 2: set 2 had 600kg, set 3 adds 500kg => total 1,100kg (> 1,000kg)
        final session2 = _session(2, DateTime(2026, 6, 8));
        final we2 = _we(2, 1, sessionId: 2);
        final set2 = _set(2, 2, weightKg: 100, reps: 6);

        final snapshot = TrainingSnapshot(
          sets: [
            _resolved(set: set1, we: we1, ex: benchEx, session: session1),
            _resolved(set: set2, we: we2, ex: benchEx, session: session2),
          ],
          exerciseMuscles: [],
        );

        final notifications = evaluator.evaluateCompletedSet(
          snapshot: snapshot,
          currentSessionId: 2,
          exerciseId: 1,
          exerciseName: 'Bench Press',
          primaryMuscle: 'Chest',
          effectiveKg: 100,
          weightKg: 100,
          reps: 5, // 500kg added => 1,100kg total
          accessoryNames: const [],
          equipmentVariant: 'barbell',
          setType: SetType.standard,
          weightFormat: weightFormat,
        );

        expect(
          notifications.any((n) => n.type == AchievementType.exerciseTonnagePr),
          isTrue,
        );
        final volPr = notifications.firstWhere(
          (n) => n.type == AchievementType.exerciseTonnagePr,
        );
        expect(volPr.badgeText.contains('EXERCISE VOLUME PR'), isTrue);
      },
    );
  });

  group('AchievementEvaluator - Finished Workout', () {
    test('detects Chest Volume PR in workout', () {
      final benchEx = _ex(1, name: 'Bench Press', primaryMuscle: 'Chest');
      final session1 = _session(
        1,
        DateTime(2026, 6, 1),
        endedAt: DateTime(2026, 6, 1, 10, 30),
      );
      final we1 = _we(1, 1, sessionId: 1);
      // Session 1: 3 sets of 100kg x 5 = 1,500kg
      final pastSets = [
        _set(1, 1, weightKg: 100, reps: 5),
        _set(2, 1, weightKg: 100, reps: 5),
        _set(3, 1, weightKg: 100, reps: 5),
      ];

      // Session 2: 5 sets of 100kg x 10 = 5,000kg Chest Volume
      final session2 = _session(
        2,
        DateTime(2026, 6, 8, 9, 0),
        endedAt: DateTime(2026, 6, 8, 10, 0),
      );
      final we2 = _we(2, 1, sessionId: 2);
      final currentSets = [
        for (var i = 0; i < 5; i++) _set(10 + i, 2, weightKg: 100, reps: 10),
      ];

      final snapshot = TrainingSnapshot(
        sets: [
          for (final s in pastSets)
            _resolved(set: s, we: we1, ex: benchEx, session: session1),
          for (final s in currentSets)
            _resolved(set: s, we: we2, ex: benchEx, session: session2),
        ],
        exerciseMuscles: [
          ExerciseMuscleData(
            id: 1,
            exerciseId: 1,
            muscle: 'Chest',
            role: 'primary',
            contribution: 1.0,
          ),
        ],
      );

      final notifications = evaluator.evaluateFinishedWorkout(
        snapshot: snapshot,
        currentSessionId: 2,
        workoutName: 'Chest Day',
        startedAt: DateTime(2026, 6, 8, 9, 0),
        endedAt: DateTime(2026, 6, 8, 10, 0),
        weightFormat: weightFormat,
        totalCompletedWorkouts: 10,
      );

      expect(
        notifications.any((n) => n.type == AchievementType.muscleGroupVolumePr),
        isTrue,
      );
      final musclePr = notifications.firstWhere(
        (n) => n.type == AchievementType.muscleGroupVolumePr,
      );
      expect(musclePr.badgeText.contains('CHEST VOLUME PR'), isTrue);
      expect(
        notifications.any((n) => n.type == AchievementType.workoutMilestone),
        isTrue,
      );
    });

    test('detects Longest Workout duration record', () {
      final benchEx = _ex(1);
      final session1 = _session(
        1,
        DateTime(2026, 6, 1, 9, 0),
        endedAt: DateTime(2026, 6, 1, 9, 45),
      ); // 45m
      final we1 = _we(1, 1, sessionId: 1);
      final pastSets = [_set(1, 1, weightKg: 100, reps: 5)];

      // Current session is 1h 20m (80m)
      final session2 = _session(
        2,
        DateTime(2026, 6, 8, 9, 0),
        endedAt: DateTime(2026, 6, 8, 10, 20),
      );
      final we2 = _we(2, 1, sessionId: 2);
      final currentSets = [_set(2, 2, weightKg: 100, reps: 5)];

      final snapshot = TrainingSnapshot(
        sets: [
          _resolved(set: pastSets[0], we: we1, ex: benchEx, session: session1),
          _resolved(
            set: currentSets[0],
            we: we2,
            ex: benchEx,
            session: session2,
          ),
        ],
        exerciseMuscles: [],
      );

      final notifications = evaluator.evaluateFinishedWorkout(
        snapshot: snapshot,
        currentSessionId: 2,
        workoutName: 'Endurance Push',
        startedAt: DateTime(2026, 6, 8, 9, 0),
        endedAt: DateTime(2026, 6, 8, 10, 20),
        weightFormat: weightFormat,
        totalCompletedWorkouts: 4,
      );

      expect(
        notifications.any((n) => n.type == AchievementType.longestWorkout),
        isTrue,
      );
    });

    test(
      'evaluateSessionSummaryAchievements collects workout and set-level PRs',
      () {
        final benchEx = _ex(1, name: 'Bench Press', primaryMuscle: 'Chest');
        final session1 = _session(
          1,
          DateTime(2026, 6, 1),
          endedAt: DateTime(2026, 6, 1, 10, 0),
        );
        final we1 = _we(1, 1, sessionId: 1);
        final pastSets = [_set(1, 1, weightKg: 100, reps: 5)]; // e1RM 114kg

        // Session 2: 120kg x 5 (e1RM 137kg => PR) + 6,000kg total volume
        final session2 = _session(
          2,
          DateTime(2026, 6, 8, 9, 0),
          endedAt: DateTime(2026, 6, 8, 10, 0),
        );
        final we2 = _we(2, 1, sessionId: 2);
        final currentSets = [
          for (var i = 0; i < 10; i++) _set(10 + i, 2, weightKg: 120, reps: 5),
        ];

        final snapshot = TrainingSnapshot(
          sets: [
            for (final s in pastSets)
              _resolved(set: s, we: we1, ex: benchEx, session: session1),
            for (final s in currentSets)
              _resolved(set: s, we: we2, ex: benchEx, session: session2),
          ],
          exerciseMuscles: [
            ExerciseMuscleData(
              id: 1,
              exerciseId: 1,
              muscle: 'Chest',
              role: 'primary',
              contribution: 1.0,
            ),
          ],
        );

        final summaryAchievements = evaluator
            .evaluateSessionSummaryAchievements(
              snapshot: snapshot,
              currentSessionId: 2,
              workoutName: 'Heavy Bench Day',
              startedAt: DateTime(2026, 6, 8, 9, 0),
              endedAt: DateTime(2026, 6, 8, 10, 0),
              weightFormat: weightFormat,
              totalCompletedWorkouts: 50,
            );

        expect(
          summaryAchievements.any(
            (a) => a.type == AchievementType.workoutTonnagePr,
          ),
          isTrue,
        );
        expect(
          summaryAchievements.any((a) => a.type == AchievementType.weightPr),
          isTrue,
        );
        expect(
          summaryAchievements.any(
            (a) => a.type == AchievementType.workoutMilestone,
          ),
          isTrue,
        );
      },
    );
  });

  group('AchievementEvaluator - Finished Fast', () {
    test('detects Longest Fast record', () {
      final pastFast = FastingSessionData(
        id: 1,
        startedAt: DateTime(2026, 6, 1, 20, 0),
        endedAt: DateTime(2026, 6, 2, 12, 0), // 16 hours
        targetSeconds: 16 * 3600,
        completed: true,
      );

      // Current fast was 20 hours
      final notifications = evaluator.evaluateFinishedFast(
        fastDuration: const Duration(hours: 20),
        pastSessions: [pastFast],
        planName: '16:8 Fast',
        targetSeconds: 16 * 3600,
      );

      expect(
        notifications.any((n) => n.type == AchievementType.longestFast),
        isTrue,
      );
      expect(
        notifications.any((n) => n.type == AchievementType.fastingTarget),
        isTrue,
      );
    });
  });
}
