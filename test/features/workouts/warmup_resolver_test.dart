import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';

void main() {
  group('WarmupResolver.resolve', () {
    test('returns empty list for non-heavy roles regardless of inputs', () {
      for (final role in [
        SlotRole.accessory,
        SlotRole.isolation,
        SlotRole.conditioning,
      ]) {
        final steps = WarmupResolver.resolve(
          role: role,
          mechanics: 'compound',
          modality: 'barbell',
          targetPercentOf1Rm: 0.92,
          isFirstHeavyLiftInSession: true,
        );
        expect(steps, isEmpty, reason: 'role=$role should be ineligible');
      }
    });

    test(
      'near-max target (>=90%) produces a dense 5-step ramp, strictly '
      'increasing percent and strictly decreasing reps',
      () {
        final steps = WarmupResolver.resolve(
          role: SlotRole.main,
          mechanics: 'compound',
          modality: 'barbell',
          targetPercentOf1Rm: 0.92,
          isFirstHeavyLiftInSession: true,
        );
        expect(steps, hasLength(5));
        for (var i = 1; i < steps.length; i++) {
          expect(
            steps[i].percentOf1Rm,
            greaterThan(steps[i - 1].percentOf1Rm),
          );
          expect(steps[i].reps, lessThan(steps[i - 1].reps));
        }
      },
    );

    test('moderate target (~70%) produces fewer steps than a 90%+ target', () {
      final dense = WarmupResolver.resolve(
        role: SlotRole.main,
        mechanics: 'compound',
        modality: 'barbell',
        targetPercentOf1Rm: 0.92,
        isFirstHeavyLiftInSession: true,
      );
      final moderate = WarmupResolver.resolve(
        role: SlotRole.main,
        mechanics: 'compound',
        modality: 'barbell',
        targetPercentOf1Rm: 0.70,
        isFirstHeavyLiftInSession: true,
      );
      expect(moderate, hasLength(3));
      expect(moderate.length, lessThan(dense.length));
    });

    test(
      'a later heavy lift in the session gets an abbreviated ramp that is '
      'a suffix/subset of the full ramp, not a different formula',
      () {
        final full = WarmupResolver.resolve(
          role: SlotRole.main,
          mechanics: 'compound',
          modality: 'barbell',
          targetPercentOf1Rm: 0.92,
          isFirstHeavyLiftInSession: true,
        );
        final abbreviated = WarmupResolver.resolve(
          role: SlotRole.main,
          mechanics: 'compound',
          modality: 'barbell',
          targetPercentOf1Rm: 0.92,
          isFirstHeavyLiftInSession: false,
        );
        expect(abbreviated.length, lessThan(full.length));
        expect(abbreviated.isNotEmpty, isTrue);
        final fullSuffix = full.sublist(full.length - abbreviated.length);
        for (var i = 0; i < abbreviated.length; i++) {
          expect(abbreviated[i].percentOf1Rm, fullSuffix[i].percentOf1Rm);
          expect(abbreviated[i].reps, fullSuffix[i].reps);
        }
      },
    );

    test('modality outside {barbell, dumbbell, kettlebell} is ineligible', () {
      final steps = WarmupResolver.resolve(
        role: SlotRole.main,
        mechanics: 'compound',
        modality: 'cable',
        targetPercentOf1Rm: 0.92,
        isFirstHeavyLiftInSession: true,
      );
      expect(steps, isEmpty);
    });

    test('null targetPercentOf1Rm falls back to the moderate/no-percent case', () {
      final steps = WarmupResolver.resolve(
        role: SlotRole.supplemental,
        mechanics: 'compound',
        modality: 'dumbbell',
        isFirstHeavyLiftInSession: true,
      );
      expect(steps, hasLength(2));
    });
  });
}
