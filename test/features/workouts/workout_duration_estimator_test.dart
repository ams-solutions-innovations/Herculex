import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';
import 'package:herculex/features/workouts/domain/workout_duration_estimator.dart';

void main() {
  group('WorkoutDurationEstimator.estimateExercise', () {
    test('standard sets: duration is strictly greater than rest-time alone and '
        'strictly less than double the same call with isUnilateral: true', () {
      const workingSets = 3;
      const repsMin = 8;
      const repsMax = 8;
      const restSeconds = 90;

      final duration = WorkoutDurationEstimator.estimateExercise(
        workingSets: workingSets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSeconds: restSeconds,
        setType: SetType.standard,
      );

      final restOnly = Duration(seconds: workingSets * restSeconds);
      expect(duration, greaterThan(restOnly));

      final unilateral = WorkoutDurationEstimator.estimateExercise(
        workingSets: workingSets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSeconds: restSeconds,
        setType: SetType.standard,
        isUnilateral: true,
      );
      final naiveDoubled = Duration(
        seconds: 2 * workingSets * (restSeconds + repsMax * 4),
      );
      expect(unilateral, lessThan(naiveDoubled));
    });

    test('isUnilateral roughly doubles the per-set working time versus '
        'bilateral, holding rest constant', () {
      const workingSets = 3;
      const repsMin = 8;
      const repsMax = 8;
      const restSeconds = 90;

      final bilateral = WorkoutDurationEstimator.estimateExercise(
        workingSets: workingSets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSeconds: restSeconds,
        setType: SetType.standard,
      );
      final unilateral = WorkoutDurationEstimator.estimateExercise(
        workingSets: workingSets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSeconds: restSeconds,
        setType: SetType.standard,
        isUnilateral: true,
      );

      // Working-set-only time (rest excluded) for bilateral:
      const secondsPerRep = 3.5;
      const avgReps = (repsMin + repsMax) / 2;
      final bilateralWorkOnly = workingSets * avgReps * secondsPerRep;
      final unilateralWorkOnly = workingSets * avgReps * secondsPerRep * 2;

      final bilateralTotal = bilateral.inSeconds;
      final unilateralTotal = unilateral.inSeconds;
      final restTotal = workingSets * restSeconds;

      expect(bilateralTotal - restTotal, closeTo(bilateralWorkOnly, 1));
      expect(unilateralTotal - restTotal, closeTo(unilateralWorkOnly, 1));
    });

    test(
      'myo-reps mini-set bursts add time beyond an equivalent standard set',
      () {
        final standard = WorkoutDurationEstimator.estimateExercise(
          workingSets: 2,
          repsMin: 10,
          repsMax: 12,
          restSeconds: 60,
          setType: SetType.standard,
        );
        final myoReps = WorkoutDurationEstimator.estimateExercise(
          workingSets: 2,
          repsMin: 10,
          repsMax: 12,
          restSeconds: 60,
          setType: SetType.myoReps,
        );
        expect(myoReps, greaterThan(standard));
      },
    );

    test('non-empty warmupSteps add time versus an empty list', () {
      const warmupSteps = [
        WarmupStep(0.40, 8),
        WarmupStep(0.55, 5),
        WarmupStep(0.70, 2),
      ];
      final withWarmup = WorkoutDurationEstimator.estimateExercise(
        workingSets: 3,
        repsMin: 8,
        repsMax: 8,
        restSeconds: 90,
        setType: SetType.standard,
        warmupSteps: warmupSteps,
      );
      final withoutWarmup = WorkoutDurationEstimator.estimateExercise(
        workingSets: 3,
        repsMin: 8,
        repsMax: 8,
        restSeconds: 90,
        setType: SetType.standard,
      );
      expect(withWarmup, greaterThan(withoutWarmup));
    });
  });

  group('WorkoutDurationEstimator.estimateCappedSegment', () {
    test('returns the cap verbatim as a Duration, no per-rep math applied', () {
      final capped = WorkoutDurationEstimator.estimateCappedSegment(
        capSeconds: 600,
      );
      expect(capped, const Duration(seconds: 600));
    });

    test('composes with estimateSession alongside a per-rep exercise', () {
      final cappedSegment = WorkoutDurationEstimator.estimateCappedSegment(
        capSeconds: 600,
      );
      final exercise = WorkoutDurationEstimator.estimateExercise(
        workingSets: 3,
        repsMin: 8,
        repsMax: 8,
        restSeconds: 90,
        setType: SetType.standard,
      );

      final total = WorkoutDurationEstimator.estimateSession([
        cappedSegment,
        exercise,
      ]);

      expect(total, cappedSegment + exercise + const Duration(seconds: 2 * 90));
    });
  });

  group('WorkoutDurationEstimator.estimateSession', () {
    test('total accounts for one inter-exercise transition per exercise, '
        'strictly greater than the sum of inputs alone', () {
      final durations = [
        const Duration(minutes: 5),
        const Duration(minutes: 8),
        const Duration(minutes: 6),
      ];
      final sumOnly = durations.fold(Duration.zero, (sum, d) => sum + d);

      final total = WorkoutDurationEstimator.estimateSession(durations);

      expect(total, greaterThan(sumOnly));
      expect(total, sumOnly + Duration(seconds: durations.length * 90));
    });
  });
}
