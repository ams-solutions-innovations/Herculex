import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/data/exercise_ergonomics_repository.dart';
import 'package:herculex/features/workouts/domain/exercise_ergonomics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExerciseErgonomicsRepository', () {
    late ExerciseErgonomicsRepository repo;

    setUp(() {
      repo = ExerciseErgonomicsRepository();
    });

    test('loads from JSON asset successfully', () async {
      await repo.load();

      final squat = repo.getForMovement('squat');
      expect(squat, isNotNull);
      expect(squat!.movementSlug, 'squat');

      final longFemur = squat.guidanceByRatio['long_femur'];
      expect(longFemur, isNotNull);
      expect(longFemur!.guidance, contains('longer femur'));
      expect(longFemur.sources, isNotEmpty);

      // Test direct ratio access
      final benchGuidance = repo.getGuidance('bench_press', 'long_arms');
      expect(benchGuidance, isNotNull);
      expect(
        benchGuidance!.guidance,
        contains('Long arms significantly increase the range of motion'),
      );
    });

    test('returns null for unknown movement or ratio', () {
      repo.seed({
        'squat': const ExerciseErgonomics(
          movementSlug: 'squat',
          guidanceByRatio: {
            'long_femur': ErgonomicGuidance(guidance: 'test', sources: []),
          },
        ),
      });

      expect(repo.getForMovement('unknown'), isNull);
      expect(repo.getGuidance('squat', 'unknown_ratio'), isNull);
      expect(repo.getGuidance('unknown_movement', 'long_femur'), isNull);
    });
  });
}
