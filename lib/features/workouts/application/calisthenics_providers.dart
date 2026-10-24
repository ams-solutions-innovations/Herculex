import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/workouts/data/calisthenics_progression_repository.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';

final calisthenicsProgressionRepositoryProvider = Provider(
  (ref) => CalisthenicsProgressionRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  ),
);

final calisthenicsRecommendationsProvider =
    StreamProvider<Map<String, CalisthenicsRecommendation>>(
      (ref) => ref
          .watch(calisthenicsProgressionRepositoryProvider)
          .watchRecommendations(),
    );
