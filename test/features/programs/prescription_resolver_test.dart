import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/prescription_resolver.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

const _flatWeek = WeekPrescription(
  weekIndex: 0,
  intensityFactor: 1,
  volumeFactor: 1,
);

void main() {
  group('archetypes', () {
    test('a max-effort main slot ramps to a top single', () {
      final p = PrescriptionResolver.archetype(
        model: PeriodizationModel.maxEffort,
        role: SlotRole.main,
        week: _flatWeek,
      );
      expect(p.segments.first.isRamp, isTrue);
    });

    test('a linear main slot does not ramp — you add load to a fixed lift', () {
      final p = PrescriptionResolver.archetype(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: _flatWeek,
      );
      expect(p.segments.every((s) => !s.isRamp), isTrue);
      expect(p.segments.first.percentOf1Rm, isNotNull);
    });

    test('block phases prescribe different main work', () {
      SlotPrescription forPhase(String phase) =>
          PrescriptionResolver.archetype(
            model: PeriodizationModel.block,
            role: SlotRole.main,
            week: WeekPrescription(
              weekIndex: 0,
              intensityFactor: 1,
              volumeFactor: 1,
              blockPhase: phase,
            ),
          );

      final accumulation = forPhase('accumulation').segments.first;
      final realization = forPhase('realization').segments.first;

      expect(accumulation.repsMin, greaterThan(realization.repsMin));
      expect(
        realization.percentOf1Rm!,
        greaterThan(accumulation.percentOf1Rm!),
      );
    });

    test('max effort puts the repetition method on the supplemental slot', () {
      final p = PrescriptionResolver.archetype(
        model: PeriodizationModel.maxEffort,
        role: SlotRole.supplemental,
        week: _flatWeek,
      );
      expect(p.hasFailureWork, isTrue);
    });

    test('every role and model combination resolves', () {
      for (final model in PeriodizationModel.values) {
        for (final role in SlotRole.values) {
          final p = PrescriptionResolver.archetype(
            model: model,
            role: role,
            week: _flatWeek,
          );
          expect(p.segments, isNotEmpty, reason: '${model.id}/${role.id}');
        }
      }
    });
  });

  group('resolve', () {
    test('a deload week cuts sets and load', () {
      const deload = WeekPrescription(
        weekIndex: 3,
        intensityFactor: 0.8,
        volumeFactor: 0.7,
        isDeload: true,
      );
      final normal = PrescriptionResolver.resolve(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: _flatWeek,
      );
      final eased = PrescriptionResolver.resolve(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: deload,
      );

      expect(
        eased.prescription.totalSets,
        lessThan(normal.prescription.totalSets),
      );
      expect(
        eased.prescription.segments.first.percentOf1Rm!,
        lessThan(normal.prescription.segments.first.percentOf1Rm!),
      );
      expect(eased.why, contains('deload'));
    });

    test('a user template overrides the archetype and is named in the why', () {
      final mine = SlotPrescription.builtIns
          .firstWhere((p) => p.name == '2 to failure');
      final r = PrescriptionResolver.resolve(
        model: PeriodizationModel.maxEffort,
        role: SlotRole.main,
        week: _flatWeek,
        template: mine,
      );
      expect(r.prescription.hasFailureWork, isTrue);
      expect(r.why, contains('2 to failure'));
    });

    test('cable and machine work drops the percentage prescription', () {
      final r = PrescriptionResolver.resolve(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: _flatWeek,
        modality: 'cable',
      );
      expect(
        r.prescription.segments.every((s) => s.percentOf1Rm == null),
        isTrue,
      );
      expect(r.why, contains('percentages do not transfer'));
    });

    test('single-joint accessory work gets higher reps', () {
      final compound = PrescriptionResolver.resolve(
        model: PeriodizationModel.none,
        role: SlotRole.accessory,
        week: _flatWeek,
      );
      final isolation = PrescriptionResolver.resolve(
        model: PeriodizationModel.none,
        role: SlotRole.accessory,
        week: _flatWeek,
        mechanics: 'isolation',
      );
      expect(
        isolation.prescription.segments.first.repsMin,
        greaterThan(compound.prescription.segments.first.repsMin),
      );
    });

    test('a heavy slot keeps its percentage even for isolation metadata', () {
      final r = PrescriptionResolver.resolve(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: _flatWeek,
        mechanics: 'isolation',
      );
      expect(r.prescription.segments.first.percentOf1Rm, isNotNull);
    });

    test('rest comes from the role unless a segment states its own', () {
      final main = PrescriptionResolver.resolve(
        model: PeriodizationModel.linear,
        role: SlotRole.main,
        week: _flatWeek,
      );
      final isolation = PrescriptionResolver.resolve(
        model: PeriodizationModel.none,
        role: SlotRole.isolation,
        week: _flatWeek,
      );
      expect(main.restSeconds, PrescriptionResolver.restByRole[SlotRole.main]);
      expect(main.restSeconds, greaterThan(isolation.restSeconds));

      final dynamicEffort = PrescriptionResolver.resolve(
        model: PeriodizationModel.maxEffort,
        role: SlotRole.main,
        week: _flatWeek,
        template: SlotPrescription.builtIns
            .firstWhere((p) => p.name == 'Dynamic Effort 8x3'),
      );
      expect(dynamicEffort.restSeconds, 60);
    });

    test('unilateral work is labelled per side', () {
      final r = PrescriptionResolver.resolve(
        model: PeriodizationModel.none,
        role: SlotRole.accessory,
        week: _flatWeek,
        unilateral: true,
      );
      expect(r.perSide, isTrue);
      expect(r.format(), endsWith('per side'));
    });

    test('the why always ends in a sentence', () {
      for (final model in PeriodizationModel.values) {
        for (final role in SlotRole.values) {
          final r = PrescriptionResolver.resolve(
            model: model,
            role: role,
            week: _flatWeek,
          );
          expect(r.why, endsWith('.'), reason: '${model.id}/${role.id}');
          expect(r.why.length, greaterThan(5));
        }
      }
    });
  });
}
