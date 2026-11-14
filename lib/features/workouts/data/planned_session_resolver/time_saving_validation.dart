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

/// Short coaching hint built from a program row's config: gear left switched
/// on, tempo, and the down-set rest rule. Null when there is nothing to say.
String? _enabledGearHint(String? configJson) {
  if (configJson == null) return null;
  try {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final gear = ((config['gear'] as List?) ?? const []).cast<String>();
    final parts = [
      if (gear.isNotEmpty)
        'Gear: ${gear.map((g) => ProgramGear.labels[g] ?? g).join(', ')}.',
      if (config['tempo'] is String) 'Tempo ${config['tempo']}.',
      if (config['downSets'] is Map)
        'Down sets: rest in seconds equals the reps you just did.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  } catch (_) {
    return null;
  }
}

/// Applies a program row's `variantConfigJson` to its planned sets: down-set
/// ladders (30, 29, 28 … 1) and per-set time / distance / calorie targets.
List<PlannedSetSnapshot> _applyRowConfig(
  List<PlannedSetSnapshot> sets,
  String? configJson,
) {
  if (configJson == null || sets.isEmpty) return sets;
  Map<String, dynamic> config;
  try {
    config = jsonDecode(configJson) as Map<String, dynamic>;
  } catch (_) {
    return sets;
  }
  var out = sets;
  final down = config['downSets'];
  if (down is Map) {
    final start = (down['startReps'] as num?)?.toInt();
    final step = ((down['decrement'] as num?)?.toInt() ?? 1).clamp(1, 1000);
    if (start != null && start > 0) {
      final template = sets.first;
      out = [
        for (var reps = start, i = 1; reps > 0; reps -= step, i++)
          PlannedSetSnapshot(
            index: i,
            repsMin: reps,
            repsMax: reps,
            isWarmup: false,
            setType: 'down_sets',
            intent: template.intent,
            rpeX10: template.rpeX10,
            rir: template.rir,
            setTypeMetaJson: jsonEncode({
              'startReps': start,
              'decrement': step,
            }),
          ),
      ];
    }
  }
  final target = config['target'];
  if (target is Map && target.isNotEmpty) {
    final prescription = <String, dynamic>{
      if (target['durationSeconds'] != null)
        'targetDurationSeconds': target['durationSeconds'],
      if (target['distanceM'] != null) 'targetDistanceM': target['distanceM'],
      if (target['calories'] != null) 'targetCalories': target['calories'],
    };
    out = [
      for (final s in out)
        s.copyWith(
          setTypeMetaJson: SetPrescriptionMetadata.encode(
            s.setTypeMetaJson,
            prescription,
          ),
        ),
    ];
  }
  return out;
}
