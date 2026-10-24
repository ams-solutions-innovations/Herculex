part of '../planned_session_resolver.dart';

extension _TargetPreparation on PlannedSessionResolver {
  PlannedSetSnapshot _templateSetSnapshot(
    int index,
    _TemplateTarget set,
    TemplateExerciseData te,
  ) {
    final prescribed = SetPrescriptionMetadata.decode(set.metaJson);
    final intent =
        prescribed['intent'] as String? ??
        (set.isWarmup ? Intent.technical.id : Intent.rir2.id);
    return PlannedSetSnapshot(
      index: index + 1,
      repsMin: set.repsMin ?? te.targetRepsMin,
      repsMax: set.repsMax ?? te.targetRepsMax ?? te.targetRepsMin,
      weightKg: set.weightKg,
      isWarmup: set.isWarmup,
      setType: set.setType,
      intent: intent,
      rir: prescribed['rir'] as int? ?? (set.isWarmup ? null : Intent.rir2.rir),
      rpeX10: prescribed.isNotEmpty
          ? prescribed['rpeX10'] as int?
          : set.isWarmup
          ? null
          : 80,
      percentOf1Rm: (prescribed['percentOf1Rm'] as num?)?.toDouble(),
      setTypeMetaJson: set.metaJson,
    );
  }

  Future<PlannedSessionSnapshot> _prepareTargets(
    PlannedSessionSnapshot plan,
    DateTime at,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final recommendations = await CalisthenicsProgressionRepository(
      _db,
      _SessionStartClock(at),
    ).recommendations();
    final targets = WorkoutTargetsRepository(
      _db,
      _SessionStartClock(at),
      prefs,
    );
    final prepared = <PlannedExerciseSnapshot>[];
    for (final original in plan.exercises) {
      var exercise = original;
      var catalog = await (_db.select(
        _db.exerciseCatalog,
      )..where((t) => t.id.equals(original.exerciseId))).getSingle();
      final level = calisthenicsLevelFor(
        catalog.slug,
        original.equipmentVariant,
      );
      final rec = recommendations[calisthenicsPathFor(catalog.slug)?.id];
      final alreadyStrict =
          rec != null &&
          {'bodyweight', 'weighted'}.contains(rec.current.variant);
      final strictLevel = rec?.path.levels
          .where((l) => l.variant == 'bodyweight')
          .firstOrNull;
      final targetLevel = alreadyStrict
          ? strictLevel
          : rec?.ready == true && rec?.target.variant == 'bodyweight'
          ? rec?.target
          : null;
      if (level != null &&
          rec != null &&
          targetLevel != null &&
          rec.path.id.startsWith('pull-up') &&
          {'band', 'machine_selectorized'}.contains(level.variant)) {
        final target =
            await (_db.select(_db.exerciseCatalog)
                  ..where(
                    (t) =>
                        t.slug.equals(targetLevel.slug) & t.deletedAt.isNull(),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (target != null) {
          exercise = _copyExercise(
            original,
            exerciseId: target.id,
            variant: 'bodyweight',
            why:
                'Strict pull-up selected from completed training history. ${original.why}',
            sets: [
              for (final set in original.sets)
                _promotedSet(set, original, targetLevel.min),
            ],
          );
          catalog = target;
        }
      }
      // Smart-program slots use role-based defaults (for example 4 × 8 for a
      // supplemental pull). A calisthenics path already has its own
      // history-aware three-set progression, so use that for a new smart slot.
      // Manually authored templates and program prescriptions remain untouched.
      final activeLevel = calisthenicsLevelFor(
        catalog.slug,
        exercise.equipmentVariant,
      );
      final activeRecommendation =
          recommendations[calisthenicsPathFor(catalog.slug)?.id];
      if (exercise.programExerciseSlotId != null &&
          activeLevel != null &&
          (activeRecommendation?.current.key == activeLevel.key ||
              (activeRecommendation?.ready == true &&
                  activeRecommendation?.target.key == activeLevel.key))) {
        exercise = _withCalisthenicsTargets(exercise, activeRecommendation!);
      }
      final resolved = await targets.resolve(
        exercise: catalog,
        workoutExercise: exercise.targetExercise,
        sets: exercise.targetRows,
      );
      final kept = <PlannedSetSnapshot>[];
      for (final set in exercise.sets) {
        final meta = _setMeta(set.setTypeMetaJson);
        final target = resolved[-set.index - 1];
        // Omit only automatically generated, calculable ramp steps. A missing
        // strength baseline must not delete a user's warmup or invent a load.
        final work = exercise.targetRows.where((s) => !s.isWarmup).firstOrNull;
        final workWeight = work == null ? null : resolved[work.id]?.weightKg;
        if (meta['automaticWarmup'] == true &&
            workWeight != null &&
            target?.reps == null)
          continue;
        kept.add(set.copyWith(index: kept.length + 1));
      }
      prepared.add(_copyExercise(exercise, sets: kept));
    }
    return PlannedSessionSnapshot(
      name: plan.name,
      exercises: prepared,
      templateId: plan.templateId,
    );
  }

  PlannedSetSnapshot _promotedSet(
    PlannedSetSnapshot s,
    PlannedExerciseSnapshot original,
    int minReps,
  ) => PlannedSetSnapshot(
    index: s.index,
    repsMin: s.isWarmup ? s.repsMin : minReps,
    repsMax: s.isWarmup ? s.repsMax : minReps,
    isWarmup: s.isWarmup,
    setType: s.setType,
    intent: s.intent,
    rpeX10: s.rpeX10,
    rir: s.rir,
    setTypeMetaJson: jsonEncode({
      ..._setMeta(s.setTypeMetaJson),
      if (_setMeta(s.setTypeMetaJson).containsKey('calisthenicsPlan'))
        'calisthenicsPlan': {'version': 1, 'variant': 'bodyweight'},
      'promotionOriginal': {
        'exerciseId': original.exerciseId,
        'variant': original.equipmentVariant,
        'why': original.why,
        'repsMin': s.repsMin,
        'repsMax': s.repsMax,
        'weightKg': s.weightKg,
        'rpeX10': s.rpeX10,
        'rir': s.rir,
        'percentOf1Rm': s.percentOf1Rm,
        'intent': s.intent,
        'meta': s.setTypeMetaJson,
      },
    }),
  );

  PlannedExerciseSnapshot _withCalisthenicsTargets(
    PlannedExerciseSnapshot exercise,
    CalisthenicsRecommendation recommendation,
  ) {
    final working = exercise.sets
        .where((set) => !set.isWarmup && set.setType == 'standard')
        .toList();
    if (working.isEmpty) return exercise;

    // Keep warm-up and advanced-technique rows intact. Only the generic
    // working prescription is replaced with the authored progression dose.
    var remaining = CalisthenicsProgression.requiredSets;
    final sets = <PlannedSetSnapshot>[];
    for (final set in exercise.sets) {
      final isWorking = !set.isWarmup && set.setType == 'standard';
      if (isWorking && remaining-- <= 0) continue;
      sets.add(
        isWorking
            ? set.copyWith(
                repsMin: recommendation.value,
                repsMax: recommendation.value,
                rpeX10: 80,
                rir: 2,
              )
            : set,
      );
    }
    return _copyExercise(exercise, sets: sets);
  }

  Map<String, dynamic> _setMeta(String? raw) {
    try {
      return jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  PlannedExerciseSnapshot _copyExercise(
    PlannedExerciseSnapshot e, {
    int? exerciseId,
    String? variant,
    String? why,
    required List<PlannedSetSnapshot> sets,
  }) => PlannedExerciseSnapshot(
    exerciseId: exerciseId ?? e.exerciseId,
    orderIndex: e.orderIndex,
    restSeconds: e.restSeconds,
    slotRole: e.slotRole,
    trainingMethod: e.trainingMethod,
    why: why ?? e.why,
    sets: sets,
    allowsAdvancedTechniques: e.allowsAdvancedTechniques,
    programExerciseSlotId: e.programExerciseSlotId,
    rotationAssignmentId: e.rotationAssignmentId,
    equipmentVariant: variant ?? e.equipmentVariant,
    sessionSegment: e.sessionSegment,
    supersetGroup: e.supersetGroup,
    waveIndex: e.waveIndex,
    waveCount: e.waveCount,
  );
}

class _SessionStartClock implements Clock {
  const _SessionStartClock(this.at);
  final DateTime at;
  @override
  DateTime now() => at;
}
