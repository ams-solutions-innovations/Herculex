import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

void main() {
  group('RotationPolicy.forSlot', () {
    test(
      'max effort rotates the main lift fast — rotation is the progression',
      () {
        final p = RotationPolicy.forSlot(
          model: PeriodizationModel.maxEffort,
          role: SlotRole.main,
        );
        expect(p.everyWeeks, lessThanOrEqualTo(3));
        expect(p.rotates, isTrue);
        // Alternating between two lifts is not accommodation.
        expect(p.minPoolSize, greaterThanOrEqualTo(3));
      },
    );

    test('linear never rotates the main lift', () {
      final p = RotationPolicy.forSlot(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
      );
      expect(p.everyWeeks, 0);
      expect(p.rotates, isFalse);
    });

    test('concurrent holds the main lift longer than max effort does', () {
      final concurrent = RotationPolicy.forSlot(
        model: PeriodizationModel.concurrent,
        role: SlotRole.main,
      );
      final maxEffort = RotationPolicy.forSlot(
        model: PeriodizationModel.maxEffort,
        role: SlotRole.main,
      );
      expect(concurrent.everyWeeks, greaterThan(maxEffort.everyWeeks));
    });

    test(
      'block locks the main lift inside a phase and forces it at the edge',
      () {
        final p = RotationPolicy.forSlot(
          model: PeriodizationModel.block,
          role: SlotRole.main,
          blockPhase: 'accumulation',
        );
        expect(p.lockedInPhase, isTrue);
        expect(p.forceOnPhaseChange, isTrue);
        expect(p.tier, PoolTier.volumeFriendly);
      },
    );

    test('realization pins the main slot to the anchor lift', () {
      final p = RotationPolicy.forSlot(
        model: PeriodizationModel.block,
        role: SlotRole.main,
        blockPhase: 'realization',
      );
      expect(p.tier, PoolTier.exactMain);
      expect(p.forceOnPhaseChange, isFalse);
    });

    test('accessories rotate freely under every model', () {
      for (final model in PeriodizationModel.values) {
        final p = RotationPolicy.forSlot(
          model: model,
          role: SlotRole.accessory,
        );
        expect(
          p.rotates,
          isTrue,
          reason: '${model.id} accessory should rotate',
        );
        expect(p.minPoolSize, 1);
      }
    });
  });

  group('RotationPolicy.epochFor', () {
    test('a fixed cadence groups weeks into equal epochs', () {
      const p = RotationPolicy(everyWeeks: 2, minGapWeeks: 2, minPoolSize: 1);
      expect(p.epochFor(0), 0);
      expect(p.epochFor(1), 0);
      expect(p.epochFor(2), 1);
      expect(p.epochFor(3), 1);
      expect(p.epochFor(4), 2);
    });

    test('everyWeeks 0 keeps one exercise for the whole program', () {
      const p = RotationPolicy(everyWeeks: 0, minGapWeeks: 0, minPoolSize: 1);
      expect(p.epochFor(0), 0);
      expect(p.epochFor(11), 0);
    });

    test('a phase-bound slot changes epoch only when the phase does', () {
      final phases = RotationPolicy.phasesFor(PeriodizationModel.block, 6);
      final p = RotationPolicy.forSlot(
        model: PeriodizationModel.block,
        role: SlotRole.main,
        blockPhase: phases.first,
      );

      final epochs = [
        for (var w = 0; w < 6; w++) p.epochFor(w, phases: phases),
      ];

      // Monotonic, starts at 0, and increments exactly once per phase change.
      expect(epochs.first, 0);
      for (var i = 1; i < epochs.length; i++) {
        expect(epochs[i] - epochs[i - 1], anyOf(0, 1));
      }

      final phaseChanges = [
        for (var w = 1; w < phases.length; w++)
          if (phases[w] != phases[w - 1]) w,
      ];
      expect(epochs.last, phaseChanges.length);
    });

    test('a week past the end of the plan clamps instead of throwing', () {
      final phases = RotationPolicy.phasesFor(PeriodizationModel.block, 4);
      final p = RotationPolicy.forSlot(
        model: PeriodizationModel.block,
        role: SlotRole.main,
        blockPhase: 'accumulation',
      );
      expect(() => p.epochFor(99, phases: phases), returnsNormally);
    });
  });
}
