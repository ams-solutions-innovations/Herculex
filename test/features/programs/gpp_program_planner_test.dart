import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/gpp_program_planner.dart';
import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

void main() {
  group('GppProgramPlanner.segmentNeedsFor', () {
    test('returns exactly one conditioning-role metcon-segment need', () {
      final needs = GppProgramPlanner.segmentNeedsFor();

      expect(needs.length, 1);
      expect(needs.single.role, SlotRole.conditioning);
      expect(needs.single.segment, SessionSegment.metcon);
    });

    test(
      'never emits SlotRole.main or SlotRole.supplemental — the '
      'role.isHeavy-gated Dynamic-Effort guard structurally cannot fire',
      () {
        final needs = GppProgramPlanner.segmentNeedsFor();

        expect(needs.any((n) => n.role == SlotRole.main), isFalse);
        expect(needs.any((n) => n.role == SlotRole.supplemental), isFalse);
        expect(needs.any((n) => n.role.isHeavy), isFalse);
      },
    );

    test(
      'no warmup/skill/strength/cooldown segments — GPP is narrow, '
      'conditioning-only content, not a multi-segment CrossFit blueprint',
      () {
        final needs = GppProgramPlanner.segmentNeedsFor();

        final segments = needs.map((n) => n.segment).toSet();
        expect(segments.contains(SessionSegment.warmup), isFalse);
        expect(segments.contains(SessionSegment.skill), isFalse);
        expect(segments.contains(SessionSegment.strength), isFalse);
        expect(segments.contains(SessionSegment.cooldown), isFalse);
      },
    );
  });

  group('SlotRoleEligibility DE-guard interaction (documented, not re-tested here)', () {
    test(
      'SlotRole.conditioning is derivable for a synthetic cardio/timed '
      'exercise, but GppProgramPlanner never returns SlotRole.main or '
      '.supplemental, so it never becomes eligible for the .isHeavy-gated '
      'Dynamic-Effort branch in smart_program_planner.dart',
      () {
        final mask = SlotRoleEligibility.derive(
          mechanics: 'isolation',
          modality: 'bodyweight',
          cnsScore: 3,
          loggingMetric: 'time',
          category: 'cardio',
        );

        expect(SlotRoleEligibility.allows(mask, SlotRole.conditioning), isTrue);
        expect(SlotRoleEligibility.allows(mask, SlotRole.main), isFalse);
        expect(SlotRoleEligibility.allows(mask, SlotRole.supplemental), isFalse);

        // The full end-to-end "populate() never emits dynamicEffort for a
        // GPP day" regression test (exercising `_methodFor` through
        // `SmartProgramPlanner.populate()`) is explicitly deferred to Plan
        // 21-06, where the wiring from GppProgramPlanner into
        // smart_program_planner.dart actually exists to run it.
        final needs = GppProgramPlanner.segmentNeedsFor();
        for (final need in needs) {
          expect(need.role.isHeavy, isFalse);
        }
      },
    );
  });
}
