import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/time_saving_policy.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';

void main() {
  TimeSavingPrescription? resolve({
    bool allowed = true,
    int minutes = 30,
    ExperienceLevel experience = ExperienceLevel.intermediate,
    TrainingGoal goal = TrainingGoal.hypertrophy,
    SlotRole role = SlotRole.isolation,
    String mechanics = 'isolation',
    String modality = 'cable',
    int sets = 3,
    int cns = 1,
    bool deloadOrPeak = false,
    bool hasTimePressure = false,
    String muscle = 'Biceps',
    TimeSavingTechnique technique = TimeSavingTechnique.automatic,
  }) => TimeSavingPolicy.resolve(
    allowed: allowed,
    sessionMinutes: minutes,
    experience: experience,
    goal: goal,
    role: role,
    mechanics: mechanics,
    modality: modality,
    availableSets: sets,
    cnsScore: cns,
    deloadOrPeak: deloadOrPeak,
    technique: technique,
    hasTimePressure: hasTimePressure,
    primaryMuscle: muscle,
  );

  test(
    'short sessions do not override consent, experience, recovery or movement safety',
    () {
      expect(resolve(allowed: false), isNull);
      expect(resolve(experience: ExperienceLevel.novice), isNull);
      expect(resolve(deloadOrPeak: true), isNull);
      expect(resolve(minutes: 60), isNull);
      expect(resolve(role: SlotRole.main), isNull);
      expect(resolve(mechanics: 'compound'), isNull);
      expect(resolve(cns: 5), isNull);
      expect(resolve(modality: 'bodyweight'), isNull);
      expect(resolve(goal: TrainingGoal.athletic), isNull);
      expect(resolve(goal: TrainingGoal.strength), isNull);
      expect(resolve(muscle: 'Neck'), isNull);
    },
  );

  test(
    'a longer target can still require compression when the full plan exceeds it',
    () {
      expect(resolve(minutes: 60, hasTimePressure: true), isNotNull);
      expect(
        resolve(minutes: 60, technique: TimeSavingTechnique.twoToFailure),
        isNotNull,
      );
    },
  );

  test(
    'automatic uses a practical method for the actual loading equipment',
    () {
      expect(resolve()!.prescription.segments.last.setType, SetType.drop);
      expect(
        resolve(modality: 'dumbbell')!.prescription.segments.single.setType,
        SetType.myoReps,
      );
      expect(
        resolve(modality: 'band', technique: TimeSavingTechnique.dropSets),
        isNull,
      );
    },
  );

  test(
    'two failure sets preserve the available dose and require a separate primer',
    () {
      final result = resolve(technique: TimeSavingTechnique.twoToFailure)!;
      expect(result.prescription.totalSets, 2);
      expect(result.prescription.hasFailureWork, isTrue);
      expect(result.isolationPrimer, isTrue);
      expect(
        resolve(sets: 1, technique: TimeSavingTechnique.twoToFailure),
        isNull,
      );
      expect(
        resolve(
          modality: 'barbell',
          technique: TimeSavingTechnique.twoToFailure,
        ),
        isNull,
      );
      final warmups = WarmupResolver.resolve(
        role: SlotRole.isolation,
        mechanics: 'isolation',
        modality: 'cable',
        isFirstHeavyLiftInSession: false,
        singleIsolationPrimer: true,
      );
      expect(warmups, hasLength(1));
      expect(warmups.single.reps, 8);
    },
  );

  test('a compact isolation primer never shortens a heavy compound ramp', () {
    final steps = WarmupResolver.resolve(
      role: SlotRole.main,
      mechanics: 'compound',
      modality: 'barbell',
      targetPercentOf1Rm: .9,
      isFirstHeavyLiftInSession: true,
      singleIsolationPrimer: true,
    );
    expect(steps.length, greaterThan(1));
  });

  test(
    'drop and myo prescriptions carry actual work and execution metadata',
    () {
      final drop = resolve()!.prescription;
      expect(drop.totalSets, 2);
      expect(drop.segments.first.setType, SetType.standard);
      expect(drop.segments.last.meta['dropPercent'], 20);
      expect(drop.segments.last.meta['relativeToTopSetMin'], .8);
      expect(drop.hasFailureWork, isFalse);
      final myo = resolve(technique: TimeSavingTechnique.myoReps)!.prescription;
      expect(myo.segments.single.meta['miniSets'], 3);
      expect(myo.hasFailureWork, isFalse);
    },
  );
}
