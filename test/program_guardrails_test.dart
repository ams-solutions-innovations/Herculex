import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
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
          containsAll([
            'config_max_effort_per_week',
            'config_six_day_ppl_max_effort',
          ]),
        );
        expect(issues, hasLength(2));
      },
    );
  });

  group('validateKgIncrease', () {
    test(
      'novice with a 90 kg increase (exceeds 50 kg ceiling) returns one warning issue',
      () {
        final issues = ProgramGuardrails.validateKgIncrease(
          specialization: const PrimaryLiftSpecialization(
            lift: PrimaryLift.squat,
            currentKg: 50,
            targetKg: 140,
            weeks: 16,
            stickingPoint: PrimaryLiftStickingPoint.bottom,
          ),
          experience: ExperienceLevel.novice,
        );

        expect(issues, hasLength(1));
        expect(issues.single.severity, GuardrailSeverity.warning);
        expect(issues.single.message, contains('Adding 90 kg to your Squat'));
        expect(issues.single.message, contains('novice lifters'));
      },
    );

    test(
      'novice with a 40 kg increase (under 50 kg ceiling) returns empty',
      () {
        final issues = ProgramGuardrails.validateKgIncrease(
          specialization: const PrimaryLiftSpecialization(
            lift: PrimaryLift.squat,
            currentKg: 100,
            targetKg: 140,
            weeks: 16,
            stickingPoint: PrimaryLiftStickingPoint.bottom,
          ),
          experience: ExperienceLevel.novice,
        );

        expect(issues, isEmpty);
      },
    );

    test(
      'intermediate with a 35 kg increase (exceeds 30 kg ceiling) returns one issue',
      () {
        final issues = ProgramGuardrails.validateKgIncrease(
          specialization: const PrimaryLiftSpecialization(
            lift: PrimaryLift.deadlift,
            currentKg: 100,
            targetKg: 135,
            weeks: 12,
            stickingPoint: PrimaryLiftStickingPoint.offFloor,
          ),
          experience: ExperienceLevel.intermediate,
        );

        expect(issues, hasLength(1));
      },
    );

    test(
      'intermediate with a 25 kg increase (under 30 kg ceiling) returns empty',
      () {
        final issues = ProgramGuardrails.validateKgIncrease(
          specialization: const PrimaryLiftSpecialization(
            lift: PrimaryLift.deadlift,
            currentKg: 100,
            targetKg: 125,
            weeks: 12,
            stickingPoint: PrimaryLiftStickingPoint.offFloor,
          ),
          experience: ExperienceLevel.intermediate,
        );

        expect(issues, isEmpty);
      },
    );

    test(
      'advanced with exactly a 15 kg increase (boundary is strictly >) returns empty',
      () {
        final issues = ProgramGuardrails.validateKgIncrease(
          specialization: const PrimaryLiftSpecialization(
            lift: PrimaryLift.benchPress,
            currentKg: 100,
            targetKg: 115,
            weeks: 12,
            stickingPoint: PrimaryLiftStickingPoint.chest,
          ),
          experience: ExperienceLevel.advanced,
        );

        expect(issues, isEmpty);
      },
    );

    test('every returned issue is warning-severity, never blocking', () {
      final issues = ProgramGuardrails.validateKgIncrease(
        specialization: const PrimaryLiftSpecialization(
          lift: PrimaryLift.overheadPress,
          currentKg: 20,
          targetKg: 100,
          weeks: 12,
          stickingPoint: PrimaryLiftStickingPoint.bottom,
        ),
        experience: ExperienceLevel.advanced,
      );

      expect(issues, isNotEmpty);
      expect(
        issues.every((i) => i.severity == GuardrailSeverity.warning),
        isTrue,
      );
    });
  });

  group('validateVolumeFloor', () {
    test(
      'a group below its minimum returns one issue with group/sets/minimum in the message',
      () {
        final issues = ProgramGuardrails.validateVolumeFloor({'Chest': 4});

        expect(issues, hasLength(1));
        expect(issues.single.severity, GuardrailSeverity.warning);
        expect(issues.single.message, contains('Chest'));
        expect(issues.single.message, contains('4 sets/week'));
        expect(issues.single.message, contains('8-set minimum'));
      },
    );

    test('a group within its band returns empty', () {
      final issues = ProgramGuardrails.validateVolumeFloor({'Quads': 16});

      expect(issues, isEmpty);
    });

    test(
      'an unmapped group falls back to the generic band and still flags low volume',
      () {
        final issues = ProgramGuardrails.validateVolumeFloor({
          'Unknown Group': 2,
        });

        expect(issues, hasLength(1));
        expect(issues.single.message, contains('Unknown Group'));
      },
    );

    test(
      'one low, one fine group returns exactly one issue, for the low group only',
      () {
        final issues = ProgramGuardrails.validateVolumeFloor({
          'Chest': 4,
          'Quads': 16,
        });

        expect(issues, hasLength(1));
        expect(issues.single.message, contains('Chest'));
      },
    );

    test('every returned issue is warning-severity, never blocking', () {
      final issues = ProgramGuardrails.validateVolumeFloor({
        'Chest': 4,
        'Back': 2,
      });

      expect(issues, isNotEmpty);
      expect(
        issues.every((i) => i.severity == GuardrailSeverity.warning),
        isTrue,
      );
    });
  });
}
