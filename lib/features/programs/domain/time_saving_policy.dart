import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

enum TimeSavingTechnique {
  automatic('automatic', 'Choose for me'),
  myoReps('myo_reps', 'Myo-reps'),
  dropSets('drop_sets', 'Drop sets'),
  twoToFailure('two_to_failure', 'Warm-up + two to failure');

  const TimeSavingTechnique(this.id, this.label);
  final String id;
  final String label;
}

class TimeSavingPrescription {
  const TimeSavingPrescription(
    this.prescription, {
    this.isolationPrimer = false,
  });
  final SlotPrescription prescription;
  final bool isolationPrimer;
}

/// Blueprint chapters 24–26 and 42; EFFORT-FAILURE-02. These are coaching
/// defaults with explicit consent, not a claim that compressed work is superior.
abstract final class TimeSavingPolicy {
  static const stableModalities = {
    'cable',
    'machine_selectorized',
    'machine_plate',
    'machine_plate_loaded',
  };

  static TimeSavingPrescription? resolve({
    required bool allowed,
    required int sessionMinutes,
    required ExperienceLevel experience,
    required TrainingGoal goal,
    required SlotRole role,
    required String mechanics,
    required String modality,
    required int availableSets,
    required int cnsScore,
    TimeSavingTechnique technique = TimeSavingTechnique.automatic,
    bool deloadOrPeak = false,
    bool hasTimePressure = false,
    String primaryMuscle = '',
  }) {
    final muscle = primaryMuscle.toLowerCase();
    if ([
      'neck',
      'sternocleidomastoid',
      'splenius',
      'lower back',
      'erector',
    ].any(muscle.contains))
      return null;
    if (!allowed ||
        (sessionMinutes > 45 &&
            !hasTimePressure &&
            technique == TimeSavingTechnique.automatic) ||
        availableSets < 1 ||
        experience == ExperienceLevel.novice ||
        deloadOrPeak ||
        (goal != TrainingGoal.hypertrophy &&
            goal != TrainingGoal.powerbuilding) ||
        role != SlotRole.isolation ||
        mechanics != 'isolation' ||
        cnsScore > 3) {
      return null;
    }
    final stable = stableModalities.contains(modality);
    if (!stable && !{'dumbbell', 'band'}.contains(modality)) return null;
    final selected = technique == TimeSavingTechnique.automatic
        ? (stable ? TimeSavingTechnique.dropSets : TimeSavingTechnique.myoReps)
        : technique;
    switch (selected) {
      case TimeSavingTechnique.twoToFailure:
        if (!stable || availableSets < 2) return null;
        return const TimeSavingPrescription(
          SlotPrescription(
            name: 'Two working sets to technical failure',
            note:
                'One separate light primer, then two controlled working sets. '
                'Stop when another clean repetition is not possible.',
            segments: [
              WorkSegment(
                sets: 2,
                repsMin: 8,
                repsMax: 15,
                intent: Intent.toFailure,
                restSeconds: 120,
              ),
            ],
          ),
          isolationPrimer: true,
        );
      case TimeSavingTechnique.dropSets:
        if (!stable || availableSets < 2) return null;
        return const TimeSavingPrescription(
          SlotPrescription(
            name: 'One set + immediate drop',
            note:
                'Reduce load by about 20% promptly after the initial set; '
                'stop at technical control rather than forcing repetitions.',
            segments: [
              WorkSegment(
                sets: 1,
                repsMin: 10,
                repsMax: 15,
                intent: Intent.rir1,
                restSeconds: 15,
              ),
              WorkSegment(
                sets: 1,
                repsMin: 10,
                repsMax: 15,
                intent: Intent.rir1,
                setType: SetType.drop,
                restSeconds: 45,
                meta: {
                  'dropPercent': 20,
                  'drops': 1,
                  'dropStep': true,
                  'relativeToTopSetMin': 0.8,
                  'relativeToTopSetMax': 0.8,
                },
              ),
            ],
          ),
        );
      case TimeSavingTechnique.myoReps:
        return const TimeSavingPrescription(
          SlotPrescription(
            name: 'Time-saving myo-reps',
            note:
                'Controlled activation plus three short mini-sets; '
                'stop when clean repetitions deteriorate.',
            segments: [
              WorkSegment(
                sets: 1,
                repsMin: 12,
                repsMax: 20,
                intent: Intent.rir1,
                setType: SetType.myoReps,
                restSeconds: 45,
                meta: {'activationReps': 15, 'miniSets': 3},
              ),
            ],
          ),
        );
      case TimeSavingTechnique.automatic:
        return null;
    }
  }
}
