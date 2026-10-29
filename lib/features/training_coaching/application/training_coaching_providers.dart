import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';

final trainingCoachingRepositoryProvider = Provider(
  (ref) => TrainingCoachingRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    health: ref.watch(healthServiceProvider),
  ),
);
final trainingCoachingProvider = StreamProvider.autoDispose
    .family<List<TrainingCoachingProposalData>, int?>((ref, sessionId) {
      ref.watch(localDayProvider);
      return ref
          .watch(trainingCoachingRepositoryProvider)
          .watch(sessionId: sessionId);
    });
final workoutBehaviorProvider = StreamProvider.autoDispose
    .family<WorkoutBehaviorSnapshotData?, int>((ref, id) async* {
      final repo = ref.watch(trainingCoachingRepositoryProvider);
      await repo.behavior.capture(id);
      yield* (repo.db.select(
        repo.db.workoutBehaviorSnapshots,
      )..where((s) => s.sessionId.equals(id))).watchSingleOrNull();
    });

final coachingFeedbackProvider = StreamProvider.autoDispose
    .family<CoachingTrialFeedback?, int>((ref, id) {
      final repo = ref.watch(trainingCoachingRepositoryProvider);
      return repo.db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              repo.db.workoutReports,
              repo.db.scheduledWorkouts,
              repo.db.trainingCoachingOverrides,
            },
          )
          .watch()
          .asyncMap((_) => repo.feedback(id));
    });
