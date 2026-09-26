import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/crossfit_program_planner.dart';
import 'package:herculex/features/programs/domain/crossfit_scaling_policy.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

void main() {
  group('CrossfitProgramPlanner.segmentNeedsFor', () {
    test('novice variationSeed 0 rotates to AMRAP with correct segment order', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.novice,
        variationSeed: 0,
      );

      final segments = needs.map((n) => n.segment).toList();
      expect(segments, [
        SessionSegment.warmup,
        SessionSegment.skill,
        SessionSegment.strength,
        SessionSegment.metcon,
        SessionSegment.metcon,
        SessionSegment.cooldown,
      ]);

      final metconNeeds = needs.where(
        (n) => n.segment == SessionSegment.metcon,
      );
      for (final need in metconNeeds) {
        expect(need.metconFormat, SetType.amrap);
        expect(need.metconCapSeconds, isNotNull);
        expect(need.metconMinutes, isNull);
      }
    });

    test('novice variationSeed 1 rotates to EMOM', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.novice,
        variationSeed: 1,
      );

      final metconNeeds = needs.where(
        (n) => n.segment == SessionSegment.metcon,
      );
      expect(metconNeeds, isNotEmpty);
      for (final need in metconNeeds) {
        expect(need.metconFormat, SetType.emom);
        expect(need.metconMinutes, isNotNull);
        expect(need.metconCapSeconds, isNull);
      }
    });

    test('novice variationSeed 2 rotates to For Time', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.novice,
        variationSeed: 2,
      );

      final metconNeeds = needs.where(
        (n) => n.segment == SessionSegment.metcon,
      );
      expect(metconNeeds, isNotEmpty);
      for (final need in metconNeeds) {
        expect(need.metconFormat, SetType.forTime);
        expect(need.metconCapSeconds, isNotNull);
      }
    });

    test('novice variationSeed 3 wraps back to AMRAP', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.novice,
        variationSeed: 3,
      );

      final metconNeeds = needs.where(
        (n) => n.segment == SessionSegment.metcon,
      );
      expect(metconNeeds, isNotEmpty);
      for (final need in metconNeeds) {
        expect(need.metconFormat, SetType.amrap);
      }
    });

    test('never emits SlotRole.main; strength is the only supplemental role', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.intermediate,
        variationSeed: 0,
      );

      expect(needs.any((n) => n.role == SlotRole.main), isFalse);

      final supplementalNeeds = needs.where(
        (n) => n.role == SlotRole.supplemental,
      );
      expect(supplementalNeeds.length, 1);
      expect(supplementalNeeds.first.segment, SessionSegment.strength);

      final nonStrengthNeeds = needs.where(
        (n) => n.segment != SessionSegment.strength,
      );
      for (final need in nonStrengthNeeds) {
        expect(need.role, SlotRole.accessory);
      }
    });

    test('all metcon needs in one call share groupKey/format/cap', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.advanced,
        variationSeed: 0,
      );

      final metconNeeds = needs
          .where((n) => n.segment == SessionSegment.metcon)
          .toList();
      expect(metconNeeds, isNotEmpty);

      final groupKeys = metconNeeds.map((n) => n.metconGroupKey).toSet();
      expect(groupKeys.length, 1);
      expect(groupKeys.single, isNotNull);

      final formats = metconNeeds.map((n) => n.metconFormat).toSet();
      expect(formats.length, 1);

      final capSeconds = metconNeeds.map((n) => n.metconCapSeconds).toSet();
      expect(capSeconds.length, 1);

      final minutes = metconNeeds.map((n) => n.metconMinutes).toSet();
      expect(minutes.length, 1);
    });

    test('advanced ceiling produces 4 metcon needs; warmup/cooldown present', () {
      final needs = CrossfitProgramPlanner.segmentNeedsFor(
        experience: ExperienceLevel.advanced,
        variationSeed: 0,
      );

      final metconNeeds = needs.where(
        (n) => n.segment == SessionSegment.metcon,
      );
      expect(
        metconNeeds.length,
        CrossfitScalingPolicy.movementCeilingFor(ExperienceLevel.advanced),
      );
      expect(metconNeeds.length, 4);

      final warmup = needs.where((n) => n.segment == SessionSegment.warmup);
      expect(warmup.length, 1);
      expect(warmup.first.role, SlotRole.accessory);

      final cooldown = needs.where(
        (n) => n.segment == SessionSegment.cooldown,
      );
      expect(cooldown.length, 1);
      expect(cooldown.first.role, SlotRole.accessory);
      expect(cooldown.first.pattern, isNull);
      expect(cooldown.first.muscle, isNull);
    });
  });
}
