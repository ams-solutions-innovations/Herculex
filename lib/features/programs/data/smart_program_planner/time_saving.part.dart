part of '../smart_program_planner.dart';

extension _TimeSavingPlans on SmartProgramPlanner {
  static _TimePlan _timePlanFor({
    required SlotRole role,
    required _Target target,
    required SmartProgramConfiguration configuration,
    required ExerciseCatalogData exercise,
    required WeekPrescription week,
    bool hasTimePressure = false,
  }) {
    final compressed = TimeSavingPolicy.resolve(
      allowed: configuration.allowTimeSavingSetTechniques,
      sessionMinutes: configuration.workoutDurationMinutes,
      experience: configuration.experience,
      goal: configuration.goal,
      role: role,
      mechanics: exercise.mechanics,
      modality: exercise.modality,
      cnsScore: exercise.cnsScore,
      availableSets: target.sets,
      technique: configuration.timeSavingTechnique,
      deloadOrPeak: week.isDeload || week.blockPhase == 'realization',
      hasTimePressure: hasTimePressure,
      primaryMuscle: exercise.primaryMuscle,
    );
    if (compressed == null) return _TimePlan.standard(target);
    final prescription = compressed.prescription;
    final work = prescription.segments;
    return _TimePlan(
      target: _Target(
        prescription.totalSets,
        work.first.repsMin,
        work.first.repsMax,
        work.last.intent.rir,
        work.first.restSeconds ?? target.restSeconds,
      ),
      setType: work.last.setType,
      isolationPrimer: compressed.isolationPrimer,
      why:
          ' ${prescription.name} fits your '
          '${configuration.workoutDurationMinutes}-minute session. '
          '${prescription.note ?? ''}',
      prescriptionCodecJson: SlotPrescriptionCodec.encode(prescription),
    );
  }
}
