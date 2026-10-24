part of '../planned_session_resolver.dart';

/// Swaps and carried user choices can change the exercise after generation.
/// Re-check a generated density method against the exercise actually performed.
(SlotPrescription?, bool, bool) _checkedTimeSavingPrescription(
  ProgramDayExerciseData row,
  ProgramData program,
  ExerciseCatalogData exercise,
  SlotRole role,
  WeekPrescription week,
  SlotPrescription? decoded,
) {
  Map<String, dynamic> config;
  try {
    config = jsonDecode(row.variantConfigJson ?? '{}') as Map<String, dynamic>;
  } catch (_) {
    return (decoded, false, false);
  }
  if (!config.containsKey('timeSavingTechnique')) {
    return (decoded, config['isolationPrimer'] == true, false);
  }
  var technique = TimeSavingTechnique.values
      .where((t) => t.id == config['timeSavingTechnique'])
      .firstOrNull;
  // Validate the stored method rather than selecting a different automatic
  // method after a swap, and retain explicit user edits to its prescription.
  if (decoded != null && technique != null) {
    if (decoded.hasFailureWork) {
      technique = TimeSavingTechnique.twoToFailure;
    } else if (decoded.segments.any((s) => s.setType.id == 'drop')) {
      technique = TimeSavingTechnique.dropSets;
    } else if (decoded.segments.any((s) => s.setType.id == 'myo_reps')) {
      technique = TimeSavingTechnique.myoReps;
    } else {
      return (decoded, false, false);
    }
  }
  final compressed = technique == null
      ? null
      : TimeSavingPolicy.resolve(
          allowed: program.allowTimeSavingSetTechniques,
          sessionMinutes:
              (config['timeSavingSessionMinutes'] as num?)?.toInt() ?? 60,
          experience: ExperienceLevel.fromId(program.experienceLevel),
          goal: TrainingGoal.fromId(program.trainingGoal),
          role: role,
          mechanics: exercise.mechanics,
          modality: exercise.modality,
          cnsScore: exercise.cnsScore,
          availableSets: row.targetSets,
          technique: technique,
          deloadOrPeak: week.isDeload || week.blockPhase == 'realization',
          hasTimePressure: true,
          primaryMuscle: exercise.primaryMuscle,
        );
  if (compressed != null) {
    return (
      decoded ?? compressed.prescription,
      compressed.isolationPrimer,
      false,
    );
  }
  return (
    SlotPrescription(
      name: 'Controlled straight sets',
      segments: [
        WorkSegment(
          sets: row.targetSets.clamp(1, 4),
          repsMin: row.targetRepsMin ?? 8,
          repsMax: row.targetRepsMax ?? row.targetRepsMin ?? 12,
          intent: Intent.rir2,
          restSeconds: exercise.mechanics == 'compound' ? 180 : 75,
        ),
      ],
    ).scaled(volumeFactor: week.volumeFactor),
    false,
    true,
  );
}
