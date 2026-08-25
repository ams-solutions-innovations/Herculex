import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

void main() {
  group('SlotRoleEligibility.derive', () {
    test('a heavy barbell compound may fill a max-effort slot', () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'compound',
        modality: 'barbell',
        cnsScore: 8,
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isTrue);
      expect(SlotRoleEligibility.allows(mask, SlotRole.supplemental), isTrue);
      expect(SlotRoleEligibility.allows(mask, SlotRole.accessory), isTrue);
    });

    test('a cable fly may never be a main lift — the whole point of the mask',
        () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'isolation',
        modality: 'cable',
        cnsScore: 2,
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
      expect(SlotRoleEligibility.allows(mask, SlotRole.isolation), isTrue);
      expect(SlotRoleEligibility.allows(mask, SlotRole.accessory), isTrue);
    });

    test('a low-CNS compound is supplemental material, not a max-effort lift',
        () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'compound',
        modality: 'barbell',
        cnsScore: 2,
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
      expect(SlotRoleEligibility.allows(mask, SlotRole.supplemental), isTrue);
    });

    test('a selectorized machine is not max-effort material either', () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'compound',
        modality: 'machine_selectorized',
        cnsScore: 8,
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
    });

    test('timed work lands in the conditioning slot', () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'compound',
        modality: 'bodyweight',
        cnsScore: 3,
        loggingMetric: 'time',
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.conditioning), isTrue);
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
    });

    test('a loaded carry is conditioning and accessory work at once', () {
      final mask = SlotRoleEligibility.derive(
        mechanics: 'compound',
        modality: 'dumbbell',
        cnsScore: 6,
        category: 'cardio',
      );
      expect(SlotRoleEligibility.allows(mask, SlotRole.conditioning), isTrue);
      expect(SlotRoleEligibility.allows(mask, SlotRole.accessory), isTrue);
    });

    test('every derived mask is non-empty', () {
      for (final mechanics in ['compound', 'isolation']) {
        for (final modality in [
          'barbell',
          'dumbbell',
          'cable',
          'machine_selectorized',
          'bodyweight',
          'band',
        ]) {
          for (final cns in [1, 5, 10]) {
            final mask = SlotRoleEligibility.derive(
              mechanics: mechanics,
              modality: modality,
              cnsScore: cns,
            );
            expect(
              SlotRoleEligibility.toList(mask),
              isNotEmpty,
              reason: '$mechanics/$modality/$cns',
            );
          }
        }
      }
    });
  });

  group('mask helpers', () {
    test('add and remove are inverses', () {
      var mask = SlotRoleEligibility.of([SlotRole.accessory]);
      mask = SlotRoleEligibility.add(mask, SlotRole.main);
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isTrue);
      mask = SlotRoleEligibility.remove(mask, SlotRole.main);
      expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
      expect(SlotRoleEligibility.allows(mask, SlotRole.accessory), isTrue);
    });

    test('the permissive default allows every role', () {
      expect(
        SlotRoleEligibility.toList(SlotRoleEligibility.all),
        SlotRole.values,
      );
    });

    test('role flags are distinct powers of two', () {
      final flags = SlotRole.values.map((r) => r.flag).toList();
      expect(flags.toSet(), hasLength(flags.length));
      for (final f in flags) {
        expect(f & (f - 1), 0, reason: '$f is not a power of two');
      }
    });

    test('only main and supplemental count as heavy', () {
      expect(SlotRole.main.isHeavy, isTrue);
      expect(SlotRole.supplemental.isHeavy, isTrue);
      expect(SlotRole.accessory.isHeavy, isFalse);
      expect(SlotRole.isolation.isHeavy, isFalse);
      expect(SlotRole.conditioning.isHeavy, isFalse);
    });

    test('an unknown id falls back to accessory', () {
      expect(SlotRole.fromId('nonsense'), SlotRole.accessory);
      expect(SlotRole.fromId(null), SlotRole.accessory);
    });
  });
}
