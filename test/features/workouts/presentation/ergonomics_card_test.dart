import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/exercise_ergonomics_repository.dart';
import 'package:herculex/features/workouts/domain/exercise_ergonomics.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_details_view.dart';

void main() {
  group('ErgonomicsCard', () {
    late ExerciseErgonomicsRepository ergoRepo;

    const squatExercise = ExerciseCatalogData(
      id: 1,
      name: 'Back Squat',
      primaryMuscle: 'Quadriceps',
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'vertical',
      defaultRestSeconds: 180,
      isCustom: false,
      category: 'strength',
      modality: 'barbell',
      cnsScore: 4,
      recoveryImpact: 4,
      movementSlug: 'squat',
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    );

    setUp(() {
      ergoRepo = ExerciseErgonomicsRepository();
      ergoRepo.seed({
        'squat': const ExerciseErgonomics(
          movementSlug: 'squat',
          guidanceByRatio: {
            'long_femur': ErgonomicGuidance(
              guidance: 'Consider a low-bar placement to center mass.',
              sources: ['Starting Strength'],
            ),
          },
        ),
      });
    });

    testWidgets('shows ergonomic guidance when user has matching proportion', (
      tester,
    ) async {
      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        heightCm: 180,
        inseamCm: 90, // 90 / 180 = 0.50 (Long)
        armSpanCm: 180, // Average
        torsoCm: 60, // Average
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) => Stream.value(profile)),
            exerciseErgonomicsRepositoryProvider.overrideWith(
              (ref) => Future.value(ergoRepo),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ErgonomicsCard(exercise: squatExercise)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Anthropometric Ergonomics'), findsOneWidget);
      expect(
        find.text('Consider a low-bar placement to center mass.'),
        findsOneWidget,
      );
      expect(find.text('Sources: Starting Strength'), findsOneWidget);
    });

    testWidgets(
      'hides ergonomic guidance when measurements are missing (ERG-03)',
      (tester) async {
        const profileWithoutMeasurements = Profile(
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.active,
          heightCm: 180,
          // No limb or torso measurements
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(
                (ref) => Stream.value(profileWithoutMeasurements),
              ),
              exerciseErgonomicsRepositoryProvider.overrideWith(
                (ref) => Future.value(ergoRepo),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: ErgonomicsCard(exercise: squatExercise)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Anthropometric Ergonomics'), findsNothing);
        expect(
          find.text('Consider a low-bar placement to center mass.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'hides when exercise has no movementSlug or no matching guidance',
      (tester) async {
        const profile = Profile(
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.active,
          heightCm: 180,
          inseamCm: 90,
          armSpanCm: 180,
          torsoCm: 60,
        );

        const unguidedExercise = ExerciseCatalogData(
          id: 2,
          name: 'Custom Bicep Curl',
          primaryMuscle: 'Biceps',
          equipment: 'Dumbbell',
          mechanics: 'isolation',
          force: 'pull',
          plane: 'vertical',
          defaultRestSeconds: 90,
          isCustom: false,
          category: 'strength',
          modality: 'dumbbell',
          cnsScore: 1,
          recoveryImpact: 1,
          movementSlug: 'bicep_curl', // Not in ergoRepo
          loggingMetric: 'weight_reps',
          supportsWeightedBodyweight: false,
          isReviewed: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith((ref) => Stream.value(profile)),
              exerciseErgonomicsRepositoryProvider.overrideWith(
                (ref) => Future.value(ergoRepo),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: ErgonomicsCard(exercise: unguidedExercise)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Anthropometric Ergonomics'), findsNothing);
      },
    );
  });
}
