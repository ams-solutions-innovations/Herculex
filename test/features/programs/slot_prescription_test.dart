import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

void main() {
  group('Intent', () {
    test('failure means zero reps in reserve', () {
      expect(Intent.toFailure.rir, 0);
      expect(Intent.toFailure.rpe, 10);
    });

    test('RIR and RPE stay in step', () {
      expect(Intent.rir2.rpe, 8);
      expect(Intent.rir3.rpe, 7);
    });

    test('an unknown id falls back rather than throwing', () {
      expect(Intent.fromId('nonsense'), Intent.rir2);
      expect(Intent.fromId(null), Intent.rir2);
    });
  });

  group('WorkSegment', () {
    test('a fixed rep target needs no explicit max', () {
      const s = WorkSegment(sets: 3, repsMin: 8);
      expect(s.repsMax, 8);
      expect(s.isRange, isFalse);
    });

    test('formats a straight set with its intent', () {
      const s = WorkSegment(sets: 3, repsMin: 8, intent: Intent.rir2);
      expect(s.format(), '3x8 @RIR2');
    });

    test('formats a percentage prescription without the RIR noise', () {
      const s = WorkSegment(
        sets: 8,
        repsMin: 3,
        intent: Intent.technical,
        percentOf1Rm: 0.55,
      );
      expect(s.format(), '8x3 @55%');
    });

    test('marks failure work', () {
      const s = WorkSegment(
        sets: 2,
        repsMin: 6,
        repsMax: 12,
        intent: Intent.toFailure,
      );
      expect(s.format(), '2x6-12→F');
    });

    test('a ramp reads as a ramp, not as sets and reps', () {
      const s = WorkSegment(sets: 1, repsMin: 1, intent: Intent.rampToMax);
      expect(s.format(), 'Work up to a heavy single');
      expect(s.isRamp, isTrue);
      expect(s.countedSets, 1);
    });

    test('failure raises the CNS multiplier above the set type alone', () {
      const plain = WorkSegment(sets: 2, repsMin: 8, intent: Intent.rir2);
      const failed = WorkSegment(sets: 2, repsMin: 8, intent: Intent.toFailure);
      expect(failed.cnsMultiplier, greaterThan(plain.cnsMultiplier));
    });

    test('the set type carries its own CNS factor through', () {
      const restPause = WorkSegment(
        sets: 2,
        repsMin: 8,
        setType: SetType.restPause,
      );
      expect(restPause.cnsMultiplier, SetType.restPause.cnsFactor);
    });
  });

  group('SlotPrescription', () {
    test('"2 to failure" is a primer plus two all-out sets', () {
      final p =
          SlotPrescription.builtIns.firstWhere((p) => p.name == '2 to failure');
      expect(p.hasFailureWork, isTrue);
      expect(p.totalSets, 3);
      expect(p.format(), '1x6-8 @RIR2 + 2x6-12→F');
    });

    test('failure composes with an advanced set type', () {
      final myo = SlotPrescription.builtIns.firstWhere((p) => p.name == 'Myo 1+3');
      expect(myo.hasFailureWork, isTrue);
      expect(myo.segments.single.setType, SetType.myoReps);
    });

    test('a ramp contributes one set to weekly volume', () {
      final me =
          SlotPrescription.builtIns.firstWhere((p) => p.name == 'Westside ME');
      expect(me.totalSets, 3);
    });

    test('scaling cuts sets and load but never scales a ramp', () {
      final me =
          SlotPrescription.builtIns.firstWhere((p) => p.name == 'Westside ME');
      final deloaded = me.scaled(intensityFactor: 0.8, volumeFactor: 0.7);

      expect(deloaded.segments.first.isRamp, isTrue);
      expect(deloaded.segments.first.sets, me.segments.first.sets);

      final backoff = deloaded.segments.last;
      expect(backoff.sets, 1); // 2 * 0.7 = 1.4 -> 1
      expect(backoff.percentOf1Rm, closeTo(0.68, 0.001));
    });

    test('scaling never drops a segment below one set', () {
      const p = SlotPrescription(
        name: 'tiny',
        segments: [WorkSegment(sets: 1, repsMin: 10)],
      );
      expect(p.scaled(volumeFactor: 0.1).segments.single.sets, 1);
    });

    test('CNS units account for both set count and technique', () {
      const plain = SlotPrescription(
        name: 'plain',
        segments: [WorkSegment(sets: 4, repsMin: 8)],
      );
      const hard = SlotPrescription(
        name: 'hard',
        segments: [
          WorkSegment(sets: 4, repsMin: 8, intent: Intent.toFailure),
        ],
      );
      expect(plain.cnsUnits, 4);
      expect(hard.cnsUnits, greaterThan(plain.cnsUnits));
    });

    test('every built-in formats without throwing', () {
      for (final p in SlotPrescription.builtIns) {
        expect(p.format(), isNotEmpty, reason: p.name);
        expect(p.totalSets, greaterThan(0), reason: p.name);
      }
    });
  });
}
