import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/crossfit_scaling_policy.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

void main() {
  group('CrossfitScalingPolicy.timeCapFor', () {
    test('AMRAP novice caps at base(600) * 0.75 = 450s', () {
      final result = CrossfitScalingPolicy.timeCapFor(
        format: SetType.amrap,
        level: ExperienceLevel.novice,
      );
      expect(result.hasCap, isTrue);
      expect(result.capSeconds, 450);
      expect(result.minutes, isNull);
      expect(result.rationale, isNotEmpty);
    });

    test('AMRAP advanced caps at base(600) * 1.25 = 750s', () {
      final result = CrossfitScalingPolicy.timeCapFor(
        format: SetType.amrap,
        level: ExperienceLevel.advanced,
      );
      expect(result.capSeconds, 750);
      expect(result.rationale, isNotEmpty);
    });

    test('For Time intermediate caps at base(720) * 1.0 = 720s', () {
      final result = CrossfitScalingPolicy.timeCapFor(
        format: SetType.forTime,
        level: ExperienceLevel.intermediate,
      );
      expect(result.capSeconds, 720);
      expect(result.rationale, isNotEmpty);
    });

    test('EMOM novice returns minutes, not capSeconds', () {
      final result = CrossfitScalingPolicy.timeCapFor(
        format: SetType.emom,
        level: ExperienceLevel.novice,
      );
      expect(result.hasCap, isTrue);
      expect(result.minutes, 9);
      expect(result.capSeconds, isNull);
      expect(result.rationale, isNotEmpty);
    });

    test('non-metcon format returns explicit noCap result', () {
      final result = CrossfitScalingPolicy.timeCapFor(
        format: SetType.standard,
        level: ExperienceLevel.novice,
      );
      expect(result.hasCap, isFalse);
      expect(result.capSeconds, isNull);
      expect(result.minutes, isNull);
      expect(result.rationale, isNotEmpty);
    });
  });

  group('CrossfitScalingPolicy.movementCeilingFor', () {
    test('returns the per-level ceiling', () {
      expect(
        CrossfitScalingPolicy.movementCeilingFor(ExperienceLevel.novice),
        2,
      );
      expect(
        CrossfitScalingPolicy.movementCeilingFor(
          ExperienceLevel.intermediate,
        ),
        3,
      );
      expect(
        CrossfitScalingPolicy.movementCeilingFor(ExperienceLevel.advanced),
        4,
      );
    });
  });

  group('CrossfitScalingPolicy.complexityCheck', () {
    test('novice at ceiling (2 movements) succeeds', () {
      final result = CrossfitScalingPolicy.complexityCheck(
        movementCount: 2,
        hasAdvancedMovement: false,
        level: ExperienceLevel.novice,
      );
      expect(result.isSafe, isTrue);
      expect(result.rationale, isNotEmpty);
    });

    test('novice exceeding ceiling (3 movements) fails', () {
      final result = CrossfitScalingPolicy.complexityCheck(
        movementCount: 3,
        hasAdvancedMovement: false,
        level: ExperienceLevel.novice,
      );
      expect(result.isSafe, isFalse);
      expect(result.rationale, isNotEmpty);
    });

    test('advanced with a single advanced movement within ceiling succeeds',
        () {
      final result = CrossfitScalingPolicy.complexityCheck(
        movementCount: 2,
        hasAdvancedMovement: true,
        level: ExperienceLevel.advanced,
      );
      expect(result.isSafe, isTrue);
    });

    test('stacking two advanced movements fails regardless of level', () {
      final result = CrossfitScalingPolicy.complexityCheck(
        movementCount: 2,
        advancedMovementCount: 2,
        level: ExperienceLevel.advanced,
      );
      expect(result.isSafe, isFalse);
      expect(result.rationale, isNotEmpty);
    });
  });

}
