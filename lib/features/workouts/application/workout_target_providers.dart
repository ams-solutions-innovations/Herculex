import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/application/performance_hint_mode_provider.dart';
import 'package:herculex/features/workouts/data/workout_targets_repository.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/workout_target_resolver.dart';

final workoutTargetsRepositoryProvider = Provider(
  (ref) => WorkoutTargetsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

final workoutProgressionGoalProvider = Provider(
  (ref) => switch (ref.watch(effectiveFitnessGoalProvider) ??
      FitnessGoal.maintenance) {
    FitnessGoal.weightLoss => ProgressionGoal.fatLoss,
    FitnessGoal.improveHealth => ProgressionGoal.endurance,
    FitnessGoal.muscleGain ||
    FitnessGoal.maintenance => ProgressionGoal.muscleGain,
  },
);

final workoutTargetsProvider = StreamProvider.autoDispose
    .family<Map<int, WorkoutTarget>, int>(
      (ref, id) => ref
          .watch(workoutTargetsRepositoryProvider)
          .watch(
            id,
            ref.watch(workoutProgressionGoalProvider),
            nextMode:
                ref.watch(performanceHintModeProvider) ==
                PerformanceHintMode.next,
          ),
    );
