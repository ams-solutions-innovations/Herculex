import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/workouts/data/exercise_history_repository.dart';

final exerciseHistoryRepositoryProvider = Provider(
  (ref) => ExerciseHistoryRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  ),
);
