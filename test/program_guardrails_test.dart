import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

void main() {
  test('Max Effort validates session count, weekly count, gap and pool', () {
    final monday = DateTime(2026, 9, 7, 8);
    final issues = ProgramGuardrails.validateMaxEffortWeek([
      GuardedProgramSlot(
        slotKey: 'a',
        sessionKey: 'monday',
        startsAt: monday,
        role: SlotRole.main,
        method: SlotTrainingMethod.maxEffort,
        movementPattern: 'squat',
        rotates: true,
        poolSize: 2,
      ),
      GuardedProgramSlot(
        slotKey: 'b',
        sessionKey: 'monday',
        startsAt: monday,
        role: SlotRole.supplemental,
        method: SlotTrainingMethod.maxEffort,
        movementPattern: 'bench',
        rotates: true,
        poolSize: 3,
      ),
      GuardedProgramSlot(
        slotKey: 'c',
        sessionKey: 'wednesday',
        startsAt: monday.add(const Duration(hours: 48)),
        role: SlotRole.main,
        method: SlotTrainingMethod.maxEffort,
        movementPattern: 'squat',
        rotates: true,
        poolSize: 3,
      ),
    ]);

    expect(
      issues.map((i) => i.code),
      containsAll([
        'max_effort_pool',
        'max_effort_per_session',
        'max_effort_per_week',
        'max_effort_gap',
      ]),
    );
  });

  test('Smart Max Effort only recommends eligible strength lifters', () {
    expect(
      ProgramGuardrails.smartMaxEffortEligible(
        level: ExperienceLevel.intermediate,
        goal: TrainingGoal.strength,
        eligibility: MaxEffortEligibility.eligible,
      ),
      isTrue,
    );
    expect(
      ProgramGuardrails.smartMaxEffortEligible(
        level: ExperienceLevel.novice,
        goal: TrainingGoal.strength,
        eligibility: MaxEffortEligibility.eligible,
      ),
      isFalse,
    );
  });

  test('Max Effort reserves fatigue budget for the rest of the day', () {
    expect(
      ProgramGuardrails.remainingFatigueBudget(
        originalBudget: 8,
        method: SlotTrainingMethod.maxEffort,
      ),
      4,
    );
  });

  group('validateConfiguration', () {
    test(
      'smart mode with 3+ explicit Max Effort days returns exactly one blocking issue',
      () {
        final issues = ProgramGuardrails.validateConfiguration(
          buildMode: ProgramBuildMode.smart,
          model: PeriodizationModel.linear,
          split: SplitType.abc,
          mainMethodByDayLabel: {
            'A': SlotTrainingMethod.maxEffort,
            'B': SlotTrainingMethod.maxEffort,
            'C': SlotTrainingMethod.maxEffort,
          },
        );

        expect(issues, hasLength(1));
        expect(
          issues.single.message,
          'A Smart program can use at most two Max Effort patterns per week.',
        );
        expect(issues.single.severity, GuardrailSeverity.blocking);
      },
    );

    test(
      'smart mode with 6-day PPL + Max Effort periodization returns the PPL issue',
      () {
        final issues = ProgramGuardrails.validateConfiguration(
          buildMode: ProgramBuildMode.smart,
          model: PeriodizationModel.maxEffort,
          split: SplitType.ppl,
          mainMethodByDayLabel: const {},
        );

        expect(
          issues.map((i) => i.message),
          contains(
            'A six-day PPL would create three Max Effort days. Use per-slot Max Effort or choose a Conjugate 3–4 day structure.',
          ),
        );
      },
    );

    test(
      'manual mode is exempt from both checks even when both trigger conditions are present',
      () {
        final issues = ProgramGuardrails.validateConfiguration(
          buildMode: ProgramBuildMode.manual,
          model: PeriodizationModel.maxEffort,
          split: SplitType.ppl,
          mainMethodByDayLabel: {
            'A': SlotTrainingMethod.maxEffort,
            'B': SlotTrainingMethod.maxEffort,
            'C': SlotTrainingMethod.maxEffort,
          },
        );

        expect(issues, isEmpty);
      },
    );

    test(
      'guided mode with neither trigger condition present returns an empty issue list',
      () {
        final issues = ProgramGuardrails.validateConfiguration(
          buildMode: ProgramBuildMode.guided,
          model: PeriodizationModel.linear,
          split: SplitType.abc,
          mainMethodByDayLabel: {'A': SlotTrainingMethod.maxEffort},
        );

        expect(issues, isEmpty);
      },
    );

    test(
      'both conditions triggered simultaneously returns both issues, not just the first',
      () {
        final issues = ProgramGuardrails.validateConfiguration(
          buildMode: ProgramBuildMode.smart,
          model: PeriodizationModel.maxEffort,
          split: SplitType.ppl,
          mainMethodByDayLabel: {
            'A': SlotTrainingMethod.maxEffort,
            'B': SlotTrainingMethod.maxEffort,
            'C': SlotTrainingMethod.maxEffort,
          },
        );

        expect(
          issues.map((i) => i.code),
          containsAll(['config_max_effort_per_week', 'config_six_day_ppl_max_effort']),
        );
        expect(issues, hasLength(2));
      },
    );
  });
}
