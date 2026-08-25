import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/circuits_repository.dart';
import 'workouts_providers.dart';

final circuitsRepositoryProvider = Provider<CircuitsRepository>((ref) {
  return CircuitsRepository(ref.watch(appDatabaseProvider));
});

final workoutCircuitsProvider = StreamProvider<List<WorkoutCircuitData>>((ref) {
  return ref.watch(circuitsRepositoryProvider).watchCircuits();
});

final circuitExercisesProvider =
    StreamProvider.family<List<CircuitExerciseData>, int>((ref, circuitId) {
  return ref.watch(circuitsRepositoryProvider).watchCircuitExercises(circuitId);
});

typedef CircuitDetails = ({
  WorkoutCircuitData circuit,
  List<({CircuitExerciseData entry, ExerciseCatalogData catalog})> exercises,
});

final circuitDetailsProvider =
    FutureProvider.family<CircuitDetails?, int>((ref, circuitId) async {
  final repo = ref.watch(circuitsRepositoryProvider);
  final circuit = await repo.getCircuitById(circuitId);
  if (circuit == null) return null;

  final entries = await repo.getCircuitExercises(circuitId);
  final snapshot = await ref.watch(workoutsRepositoryProvider).watchExerciseCatalog().first;
  final catalogMap = {for (final e in snapshot.exercises) e.id: e};

  final exerciseDetails = entries.map((entry) {
    final catalog = catalogMap[entry.exerciseId] ??
        ExerciseCatalogData(
          id: entry.exerciseId,
          name: 'Exercise #${entry.exerciseId}',
          primaryMuscle: '',
          equipment: '',
          mechanics: '',
          force: '',
          plane: '',
          defaultRestSeconds: 90,
          isCustom: false,
          category: 'strength',
          modality: 'barbell',
          cnsScore: 3,
          recoveryImpact: 3,
          loggingMetric: 'weight_reps',
          supportsWeightedBodyweight: false,
          isReviewed: false,
        );
    return (entry: entry, catalog: catalog);
  }).toList();

  return (circuit: circuit, exercises: exerciseDetails);
});
