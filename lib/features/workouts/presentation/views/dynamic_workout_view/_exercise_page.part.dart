part of '../dynamic_workout_view.dart';

/// One exercise: its name, which set you are on, the two big numbers to lift,
/// and what you did last time.
class _ExercisePage extends ConsumerWidget {
  const _ExercisePage({
    required this.we,
    required this.catalogExercise,
    required this.catalog,
    required this.exercises,
    required this.tags,
    required this.sets,
    required this.activeSet,
    required this.activeSetIndex,
    required this.onSelectSet,
    required this.onOpenRpe,
  });

  final WorkoutExerciseData we;
  final ExerciseCatalogData? catalogExercise;
  final List<ExerciseCatalogData> catalog;
  final List<WorkoutExerciseData> exercises;
  final Map<int, String> tags;
  final List<SetEntryData> sets;
  final SetEntryData? activeSet;
  final int activeSetIndex;
  final ValueChanged<int> onSelectSet;
  final void Function(SetEntryData set, int index) onOpenRpe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final exercise = catalogExercise;
    final metric = exercise != null
        ? effectiveLoggingMetric(
            exercise: exercise,
            equipmentVariant: we.equipmentVariant,
          )
        : LoggingMetric.weightReps;
    final active = activeSet;
    final target = active == null
        ? null
        : ref.watch(workoutTargetsProvider(we.id)).valueOrNull?[active.id];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  if (we.supersetGroup != null) ...[
                    _SupersetStrip(
                      we: we,
                      exercises: exercises,
                      catalog: catalog,
                      tags: tags,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (exercise != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.selection();
                        context.push(AppPaths.exercise(exercise.id));
                      },
                      child: Column(
                        children: [
                          Text(
                            exercise.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 32,
                              height: 1.08,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            equipmentVariantLabel(
                              we.equipmentVariant ?? exercise.modality,
                            ),
                            style: TextStyle(
                              color: hx.secondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (sets.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No sets added for this exercise',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: hx.secondary,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    if (exercise != null)
                      CalisthenicsProgressionCard(
                        exercise: exercise,
                        workoutExercise: we,
                      ),
                    if (active != null) ...[
                      const SizedBox(height: 18),
                      _SetHeadline(
                        set: active,
                        number: numberSets(sets)[activeSetIndex],
                        targetRpeX10: active.plannedRpeX10 ?? target?.rpeX10,
                        onTap: () => onOpenRpe(active, activeSetIndex),
                      ),
                    ],
                    if (sets.length > 1) ...[
                      const SizedBox(height: 10),
                      _SetChips(
                        sets: sets,
                        activeSetIndex: activeSetIndex,
                        onSelect: (i) {
                          Haptics.selection();
                          onSelectSet(i);
                        },
                      ),
                    ],
                    const Spacer(),
                    if (active != null) ...[
                      _Metrics(
                        set: active,
                        target: target,
                        metric: metric,
                        assistance: isMachineAssistedPullup(exercise?.slug),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.swipe_vertical_rounded,
                            size: 15,
                            color: hx.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Flick up or down to adjust · tap to type',
                            style: TextStyle(
                              color: hx.tertiary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      _ExtraRepsSection(set: active),
                      _DynamicSetAccessoryPills(setId: active.id),
                      if (exercise != null)
                        _LastTimePill(
                          exerciseId: exercise.id,
                          setIndex: activeSetIndex,
                        ),
                    ],
                    const Spacer(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `SUPERSET  A1 · Incline DB  A2 · Cable Fly`, with this exercise lit.
class _SupersetStrip extends StatelessWidget {
  const _SupersetStrip({
    required this.we,
    required this.exercises,
    required this.catalog,
    required this.tags,
  });

  final WorkoutExerciseData we;
  final List<WorkoutExerciseData> exercises;
  final List<ExerciseCatalogData> catalog;
  final Map<int, String> tags;

  @override
  Widget build(BuildContext context) {
    final mates = exercises
        .where((e) => e.supersetGroup == we.supersetGroup)
        .toList();
    final label = switch (mates.length) {
      <= 2 => 'SUPERSET',
      3 => 'TRI-SET',
      _ => 'GIANT SET',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: supersetCyan.withValues(alpha: 0.10),
        borderRadius: HxRadius.pillAll,
        border: Border.all(color: supersetCyan.withValues(alpha: 0.35)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 15, color: supersetCyan),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: workoutKicker(
                      context,
                      color: supersetCyan,
                      size: 10.5,
                      spacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            for (final mate in mates) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: mate.id == we.id ? supersetCyan : Colors.transparent,
                  borderRadius: HxRadius.pillAll,
                ),
                child: Text(
                  '${tags[mate.id] ?? ''} · ${catalog.firstWhereOrNull((c) => c.id == mate.exerciseId)?.name ?? 'Exercise'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mate.id == we.id
                        ? const Color(0xFF04121A)
                        : Color.lerp(supersetCyan, Colors.white, 0.4),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Weight × reps (or time), as big as the screen allows.
class _Metrics extends ConsumerWidget {
  const _Metrics({
    required this.set,
    required this.target,
    required this.metric,
    required this.assistance,
  });

  final SetEntryData set;
  final WorkoutTarget? target;
  final LoggingMetric metric;
  final bool assistance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final weightFmt = ref.watch(weightFormatProvider);
    final repo = ref.read(workoutsRepositoryProvider);
    final hasWeight = metric.has(SetField.weight);
    final hasReps = metric.isRepBased;
    final hasDuration = metric.has(SetField.duration);
    final count =
        (hasWeight ? 1 : 0) + (hasReps ? 1 : 0) + (hasDuration ? 1 : 0);
    final fontSize = count <= 2 ? 96.0 : 64.0;

    final pickers = <Widget>[
      if (hasWeight)
        _FlickNumberPicker(
          key: ValueKey('w_${set.id}_${set.weightKg}'),
          label: assistance
              ? 'ASSISTANCE ${weightFmt.suffix.toUpperCase()}'
              : weightFmt.suffix.toUpperCase(),
          value: set.hasEnteredWeight ? set.weightKg : target?.weightKg ?? 0,
          step: 0.5,
          min: 0.0,
          max: 999.0,
          fontSize: fontSize,
          displayFormatter: (val) => weightFmt.formatValue(val),
          onChanged: (kg) =>
              repo.updateSet(setId: set.id, weightKg: kg.clamp(0.0, 999.0)),
        ),
      if (hasReps)
        _FlickNumberPicker(
          key: ValueKey('r_${set.id}_${set.reps}'),
          label: 'REPS',
          value: (set.reps > 0 ? set.reps : target?.reps ?? 0).toDouble(),
          step: 1.0,
          min: 1.0,
          max: 999.0,
          isInteger: true,
          fontSize: fontSize,
          displayFormatter: (val) => val.toInt().toString(),
          onChanged: (reps) =>
              repo.updateSet(setId: set.id, reps: reps.toInt().clamp(1, 999)),
        ),
      if (hasDuration)
        _FlickNumberPicker(
          key: ValueKey('d_${set.id}_${set.durationSeconds}'),
          label: 'SEC',
          value: (set.durationSeconds ?? 30).toDouble(),
          step: 5.0,
          min: 1.0,
          max: 3600.0,
          isInteger: true,
          fontSize: fontSize,
          displayFormatter: (val) => val.toInt().toString(),
          onChanged: (sec) => repo.updateSet(
            setId: set.id,
            durationSeconds: sec.toInt().clamp(1, 3600),
          ),
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < pickers.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Text(
                i == 1 && hasWeight && hasReps ? '×' : '·',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w400,
                  color: hx.outline,
                ),
              ),
            ),
          Expanded(child: pickers[i]),
        ],
      ],
    );
  }
}

/// `Last time 77.5 kg × 8` — the same set from the previous session.
class _LastTimePill extends ConsumerWidget {
  const _LastTimePill({required this.exerciseId, required this.setIndex});

  final int exerciseId;
  final int setIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final weightFmt = ref.watch(weightFormatProvider);
    final last = ref.watch(lastPerformanceProvider(exerciseId)).valueOrNull;
    final sets = last?.sets ?? const <SetEntryData>[];
    final set = sets.elementAtOrNull(setIndex) ?? sets.lastOrNull;
    if (set == null) return const SizedBox(height: 14);
    final value = [
      if (set.weightKg > 0) weightFmt.format(set.weightKg),
      if (set.reps > 0) '${set.reps}',
      if (set.weightKg <= 0 && set.reps <= 0 && set.durationSeconds != null)
        '${set.durationSeconds} s',
    ].join(' × ');
    if (value.isEmpty) return const SizedBox(height: 14);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: hx.surfaceContainer.withValues(alpha: 0.8),
          borderRadius: HxRadius.pillAll,
          border: Border.all(color: hx.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 16, color: hx.secondary),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                text: 'Last time ',
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: hx.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                color: hx.onSurfaceVariant,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
