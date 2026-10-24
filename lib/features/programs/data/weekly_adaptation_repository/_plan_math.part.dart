part of '../weekly_adaptation_repository.dart';

void _addPlanVolume(
  Map<String, double> total,
  PlannedSessionSnapshot plan,
  Map<int, List<ExerciseMuscleData>> musclesByExercise,
  Map<int, ExerciseCatalogData> catalogById,
) {
  for (final exercise in plan.exercises) {
    final credit = _exerciseVolume(
      exercise.exerciseId,
      exercise.sets.where((set) => !set.isWarmup).length,
      musclesByExercise,
      catalogById,
    );
    for (final entry in credit.entries) {
      total[entry.key] = (total[entry.key] ?? 0) + entry.value;
    }
  }
}

Map<String, double> _exerciseVolume(
  int exerciseId,
  int workingSets,
  Map<int, List<ExerciseMuscleData>> musclesByExercise,
  Map<int, ExerciseCatalogData> catalogById,
) {
  final rows = musclesByExercise[exerciseId] ?? const [];
  if (rows.isEmpty) {
    final exercise = catalogById[exerciseId];
    if (exercise == null) {
      return const {};
    }
    return {exercise.primaryMuscle: workingSets.toDouble()};
  }
  const roleWeight = {'primary': 1.0, 'secondary': 0.5, 'stabilizer': 0.2};
  return {
    for (final row in rows)
      row.muscle: workingSets * (roleWeight[row.role] ?? 0),
  };
}

AdaptedSessionPlan _adaptedPlan(PlannedSessionSnapshot plan) =>
    AdaptedSessionPlan(
      name: plan.name,
      exercises: [
        for (final exercise in plan.exercises) _adaptedExercise(exercise),
      ],
    );

AdaptedSessionPlan _reducedPlan(
  PlannedSessionSnapshot plan,
  double factor,
  Map<int, ExerciseCatalogData> catalogById,
) => AdaptedSessionPlan(
  name: plan.name,
  exercises: [
    for (final exercise in plan.exercises)
      _adaptedExercise(
        exercise,
        recoveryAdjusted: true,
        maxSets: _reducedWorkingSetCount(
          exercise,
          factor,
          catalogById[exercise.exerciseId],
        ),
      ),
  ],
);

int? _reducedWorkingSetCount(
  PlannedExerciseSnapshot exercise,
  double factor,
  ExerciseCatalogData? catalog,
) {
  if (factor >= 1) {
    return null;
  }
  final workingSets = exercise.sets.where((set) => !set.isWarmup).length;
  if (workingSets == 0) {
    return null;
  }

  // Main movement quality matters more than accumulating fatigued volume.
  // Keep up to two prescribed compound sets and never turn them into forced
  // reps: the CNS guide explicitly advises against forced reps when CNS
  // fatigue is elevated.
  if (catalog?.mechanics == 'compound') {
    return workingSets > 2 ? 2 : null;
  }

  if (exercise.slotRole != 'accessory' && exercise.slotRole != 'isolation') {
    return null;
  }

  // `ceil` left a three-set accessory unchanged at -20%. Floor removes one
  // discrete set whenever possible, so the shown reduction is real.
  return (workingSets * factor).floor().clamp(1, workingSets).toInt();
}

AdaptedExercise _adaptedExercise(
  PlannedExerciseSnapshot exercise, {
  int? maxSets,
  bool recoveryAdjusted = false,
}) {
  final selected = <AdaptedSet>[];
  var working = 0;
  for (final set in exercise.sets) {
    if (!set.isWarmup && maxSets != null && working >= maxSets) {
      continue;
    }
    if (!set.isWarmup) {
      working++;
    }
    selected.add(
      AdaptedSet(
        index: selected.length + 1,
        repsMin: set.repsMin,
        repsMax: set.repsMax,
        weightKg: set.weightKg,
        rpeX10: set.rpeX10,
        rir: set.rir,
        percentOf1Rm: set.percentOf1Rm,
        isWarmup: set.isWarmup,
        setType: set.setType,
        intent: set.intent,
        setTypeMetaJson: set.setTypeMetaJson,
      ),
    );
  }
  return AdaptedExercise(
    exerciseId: exercise.exerciseId,
    orderIndex: exercise.orderIndex,
    restSeconds: exercise.restSeconds,
    slotRole: exercise.slotRole,
    trainingMethod: exercise.trainingMethod,
    why: recoveryAdjusted
        ? '${exercise.why} Adjusted to protect recovery and CNS load.'
        : exercise.why,
    sets: selected,
    allowsAdvancedTechniques: exercise.allowsAdvancedTechniques,
    programExerciseSlotId: exercise.programExerciseSlotId,
    rotationAssignmentId: exercise.rotationAssignmentId,
    equipmentVariant: exercise.equipmentVariant,
    sessionSegment: exercise.sessionSegment,
    supersetGroup: exercise.supersetGroup,
    waveIndex: exercise.waveIndex,
    waveCount: exercise.waveCount,
  );
}

String _encode(AdaptationProposal proposal) => jsonEncode({
  'trigger': proposal.trigger.name,
  'weekStart': WeeklyAdaptationRepository._iso(proposal.weekStart),
  'reason': proposal.reason,
  'fingerprint': proposal.inputFingerprint,
  'uncovered': proposal.uncoveredVolume,
  'changes': [
    for (final change in proposal.changes)
      {
        'scheduleId': change.scheduleId,
        'plan': jsonDecode(change.plan.encode()),
        'covered': change.coveredVolume,
        'addedExercise': change.addedExercise?.toJson(),
      },
  ],
});

AdaptationProposal _decode(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return AdaptationProposal(
    trigger: AdaptationTrigger.values.byName(json['trigger'] as String),
    weekStart: DateTime.parse(json['weekStart'] as String),
    reason: json['reason'] as String,
    inputFingerprint: json['fingerprint'] as String,
    uncoveredVolume: (json['uncovered'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    ),
    changes: (json['changes'] as List<dynamic>)
        .map((rawChange) {
          final change = rawChange as Map<String, dynamic>;
          return AdaptationChange(
            scheduleId: change['scheduleId'] as int,
            plan: AdaptedSessionPlan.decode(jsonEncode(change['plan'])),
            addedExercise: change['addedExercise'] == null
                ? null
                : AdaptedSessionPlan.decode(
                    jsonEncode(change['plan']),
                  ).exercises.last,
            coveredVolume: (change['covered'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            ),
          );
        })
        .toList(growable: false),
  );
}
