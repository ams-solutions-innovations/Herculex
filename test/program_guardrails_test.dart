import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

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
}
