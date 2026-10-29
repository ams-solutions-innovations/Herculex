part of '../dynamic_workout_view.dart';

/// Back to classic mode · where you are in the session (one bar segment per
/// exercise, filled by its done sets) · live elapsed time.
class _WorkoutHeader extends ConsumerWidget {
  const _WorkoutHeader({
    required this.session,
    required this.exercises,
    required this.exerciseIndex,
    required this.onExit,
  });

  final WorkoutSessionData session;
  final List<WorkoutExerciseData> exercises;
  final int exerciseIndex;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final kcal = ref
        .watch(workoutEnergyProvider(session.id))
        .valueOrNull
        ?.activeKcal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          WorkoutCircleButton(
            icon: Icons.close_fullscreen_rounded,
            tooltip: 'Classic mode',
            onTap: onExit,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'EXERCISE ${exerciseIndex + 1} / ${exercises.length}',
                      style: workoutKicker(context, size: 10.5),
                    ),
                    const Spacer(),
                    if (kcal != null)
                      Tooltip(
                        message:
                            'Estimated active calories above rest, rounded down.',
                        child: Text(
                          '≈$kcal kcal',
                          style: workoutKicker(context, size: 10.5),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < exercises.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: _ProgressSegment(
                          workoutExerciseId: exercises[i].id,
                          current: i == exerciseIndex,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: hx.surfaceContainer,
              borderRadius: HxRadius.pillAll,
              border: Border.all(color: hx.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LivePulseDot(color: hx.danger),
                const SizedBox(width: 6),
                WorkoutElapsedText(
                  startedAt: session.startedAt,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSegment extends ConsumerWidget {
  const _ProgressSegment({
    required this.workoutExerciseId,
    required this.current,
  });

  final int workoutExerciseId;
  final bool current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final sets =
        ref
            .watch(setsForWorkoutExerciseProvider(workoutExerciseId))
            .asData
            ?.value ??
        const <SetEntryData>[];
    final done = sets.where((s) => s.isCompleted).length;
    final fraction = sets.isEmpty ? 0.0 : done / sets.length;
    final color = current
        ? hx.primary
        : fraction >= 1
        ? hx.primaryText
        : hx.outline;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: hx.surfaceVariant)),
            AnimatedFractionallySizedBox(
              duration: HxMotion.base,
              widthFactor: fraction,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rest countdown folded into one line above the set, for when the
/// lifter wants the set screen back while resting. Tap to expand it again.
class _MinimizedRestPill extends ConsumerWidget {
  const _MinimizedRestPill({required this.restTimer});

  final RestTimerState restTimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final now = ref.watch(clockProvider).now();
    final remaining = restTimer.remainingSecondsFrom(now);
    final target = restTimer.targetSeconds;
    final fraction = target <= 0 ? 0.0 : (remaining / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: hx.surfaceContainer,
        shape: StadiumBorder(
          side: BorderSide(color: hx.primary.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            ref.read(dynamicRestTimerMinimizedProvider.notifier).state = false;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(height: 2, color: hx.primary),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: hx.primaryText),
                    const SizedBox(width: 10),
                    Text(
                      FullScreenRestTimerView.format(remaining),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 16,
                        color: hx.primaryText,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Rest · tap to expand',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hx.secondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _PillAction(
                      onTap: () =>
                          ref.read(restTimerProvider.notifier).addSeconds(30),
                      color: hx.primary.withValues(alpha: 0.18),
                      child: Text(
                        '+30s',
                        style: TextStyle(
                          color: hx.primaryText,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Skip rest',
                      child: _PillAction(
                        onTap: () =>
                            ref.read(restTimerProvider.notifier).cancel(),
                        color: hx.surfaceVariant,
                        square: true,
                        child: Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: hx.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.onTap,
    required this.color,
    required this.child,
    this.square = false,
  });

  final VoidCallback onTap;
  final Color color;
  final Widget child;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Haptics.light();
          onTap();
        },
        child: Container(
          height: 30,
          constraints: const BoxConstraints(minWidth: 30),
          padding: EdgeInsets.symmetric(horizontal: square ? 0 : 11),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Previous / next exercise, with the next one's name in between.
class _ExerciseStepper extends StatelessWidget {
  const _ExerciseStepper({
    required this.exercises,
    required this.catalog,
    required this.index,
    required this.onGo,
  });

  final List<WorkoutExerciseData> exercises;
  final List<ExerciseCatalogData> catalog;
  final int index;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final hasPrev = index > 0;
    final hasNext = index < exercises.length - 1;
    final nextName = hasNext
        ? catalog
                  .firstWhereOrNull(
                    (e) => e.id == exercises[index + 1].exerciseId,
                  )
                  ?.name ??
              'Next exercise'
        : 'Last exercise';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          WorkoutCircleButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous exercise',
            size: 44,
            iconSize: 26,
            onTap: hasPrev ? () => onGo(index - 1) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  'NEXT UP',
                  style: workoutKicker(context, color: hx.tertiary, size: 10.5),
                ),
                Text(
                  nextName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          WorkoutCircleButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next exercise',
            size: 44,
            iconSize: 26,
            onTap: hasNext ? () => onGo(index + 1) : null,
          ),
        ],
      ),
    );
  }
}
