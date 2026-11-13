import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

void main() {
  group('ExperienceLevel.recommend', () {
    ExperienceRecommendation recommend({
      int months = 2,
      int sessions = 6,
      bool rpe = false,
      bool blocks = false,
      ExperienceLevel? strengthLevel,
    }) => ExperienceLevel.recommend(
      consistentTrainingMonths: months,
      sessionsLast12Weeks: sessions,
      understandsRirRpe: rpe,
      hasRunStructuredBlocks: blocks,
      strengthLevel: strengthLevel,
    );

    test('little history and no strength data is still novice', () {
      expect(recommend().level, ExperienceLevel.novice);
    });

    test('an intermediate by strength is not a novice just for being new to '
        'logging (the regression)', () {
      final result = recommend(strengthLevel: ExperienceLevel.intermediate);

      expect(result.level, ExperienceLevel.intermediate);
      expect(result.reason, contains('Intermediate'));
    });

    test('a novice by strength with little history stays novice', () {
      expect(
        recommend(strengthLevel: ExperienceLevel.novice).level,
        ExperienceLevel.novice,
      );
    });

    test('strength alone never makes someone advanced', () {
      expect(
        recommend(strengthLevel: ExperienceLevel.advanced).level,
        ExperienceLevel.intermediate,
      );
    });

    test(
      'long consistent history is intermediate whatever the strength says',
      () {
        expect(
          recommend(months: 18, sessions: 40).level,
          ExperienceLevel.intermediate,
        );
        expect(
          recommend(
            months: 18,
            sessions: 40,
            strengthLevel: ExperienceLevel.novice,
          ).level,
          ExperienceLevel.intermediate,
        );
      },
    );

    test('three years of structured training is advanced', () {
      expect(
        recommend(months: 40, sessions: 36, rpe: true, blocks: true).level,
        ExperienceLevel.advanced,
      );
    });
  });
}
