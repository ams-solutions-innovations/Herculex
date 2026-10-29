part of '../dynamic_workout_view.dart';

enum _DoneStage { exercise, workout }

/// A finished exercise (every set done, next one elsewhere) or the last set
/// of the whole workout.
class _Done {
  const _Done(this.stage, this.workoutExerciseId, {this.nextIndex});

  final _DoneStage stage;
  final int workoutExerciseId;

  /// Index in the session of the exercise that comes next.
  final int? nextIndex;
}

/// The short "done" step between exercises, and before finishing: a check
/// (or trophy) that pops in, three numbers, what's next, and one button.
class _DoneScreen extends ConsumerWidget {
  const _DoneScreen({
    required this.done,
    required this.session,
    required this.exercises,
    required this.catalog,
    required this.onBack,
    required this.onContinue,
    required this.onFinish,
  });

  final _Done done;
  final WorkoutSessionData session;
  final List<WorkoutExerciseData> exercises;
  final List<ExerciseCatalogData> catalog;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final weightFmt = ref.watch(weightFormatProvider);
    final numbers = NumberFormat.decimalPattern();
    final isLast = done.stage == _DoneStage.workout;
    final accent = isLast ? hx.success : hx.primary;

    List<SetEntryData> setsOf(int workoutExerciseId) =>
        ref
            .watch(setsForWorkoutExerciseProvider(workoutExerciseId))
            .asData
            ?.value ??
        const <SetEntryData>[];
    ExerciseCatalogData? catalogOf(WorkoutExerciseData? we) => we == null
        ? null
        : catalog.firstWhereOrNull((c) => c.id == we.exerciseId);
    double volumeOf(Iterable<SetEntryData> sets) => sets
        .where((s) => s.isCompleted && !s.isWarmup)
        .fold(0.0, (sum, s) => sum + s.weightKg * s.reps);
    String volumeText(double kg) =>
        numbers.format(weightFmt.toDisplay(kg).round());

    final String kicker;
    final String title;
    final List<(String, String)> stats;
    Widget? next;

    if (isLast) {
      final all = [for (final we in exercises) ...setsOf(we.id)];
      final elapsed = ref
          .watch(clockProvider)
          .now()
          .difference(session.startedAt);
      kicker = 'THAT WAS THE LAST SET';
      title = 'Workout in the bag';
      stats = [
        (WorkoutElapsedText.format(elapsed), 'TIME'),
        ('${all.where((s) => s.isCompleted).length}', 'SETS'),
        (volumeText(volumeOf(all)), weightFmt.suffix.toUpperCase()),
      ];
    } else {
      final we = exercises.firstWhereOrNull(
        (e) => e.id == done.workoutExerciseId,
      );
      final name = catalogOf(we)?.name ?? 'Exercise';
      final sets = we == null ? const <SetEntryData>[] : setsOf(we.id);
      final working = sets.where((s) => s.isCompleted && !s.isWarmup).toList();
      final counted = working.isEmpty
          ? sets.where((s) => s.isCompleted).toList()
          : working;
      final top = counted.fold<SetEntryData?>(
        null,
        (best, s) => best == null || s.weightKg > best.weightKg ? s : best,
      );
      kicker = '${name.toUpperCase()} · ALL ${counted.length} SETS';
      title = '$name done';
      stats = [
        ('${counted.length}', 'SETS'),
        (
          volumeText(volumeOf(sets)),
          '${weightFmt.suffix.toUpperCase()} VOLUME',
        ),
        (
          top == null
              ? '—'
              : top.weightKg > 0
              ? '${weightFmt.formatValue(top.weightKg)}×${top.reps}'
              : '${top.reps} reps',
          'TOP SET',
        ),
      ];
      final nextWe = exercises.elementAtOrNull(done.nextIndex ?? -1);
      if (nextWe != null) {
        next = _UpNextCard(
          we: nextWe,
          exercise: catalogOf(nextWe),
          sets: setsOf(nextWe.id),
          tag: supersetTags(exercises)[nextWe.id],
        );
      }
    }

    return Scaffold(
      backgroundColor: hx.background,
      body: Stack(
        children: [
          Positioned(
            left: -80,
            right: -80,
            top: 40,
            height: 460,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.21),
                      accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      WorkoutCircleButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to the set',
                        onTap: onBack,
                      ),
                      const Spacer(),
                      WorkoutElapsedText(
                        startedAt: session.startedAt,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          color: hx.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                    child: Column(
                      children: [
                        _DoneBadge(
                          key: ValueKey(
                            '${done.stage}${done.workoutExerciseId}',
                          ),
                          color: accent,
                          icon: isLast
                              ? Icons.emoji_events_rounded
                              : Icons.check_rounded,
                          iconColor: isLast ? successInk : hx.onPrimary,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          kicker,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: workoutKicker(
                            context,
                            color: isLast ? accent : hx.primaryText,
                            spacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 34,
                            height: 1.05,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _StatStrip(stats: stats),
                      ],
                    ),
                  ),
                ),
                if (next != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: next,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: isLast
                      ? WorkoutHeroButton(
                          label: 'Finish workout',
                          trailingIcon: Icons.emoji_events_rounded,
                          color: hx.success,
                          foreground: successInk,
                          onPressed: () {
                            Haptics.medium();
                            onFinish();
                          },
                        )
                      : WorkoutHeroButton(
                          label: 'Continue',
                          trailingIcon: Icons.arrow_forward_rounded,
                          onPressed: () {
                            Haptics.selection();
                            onContinue();
                          },
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

/// Three numbers side by side in one card.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hx.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (value, label) in stats)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: workoutKicker(context, size: 10.5, spacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpNextCard extends ConsumerWidget {
  const _UpNextCard({
    required this.we,
    required this.exercise,
    required this.sets,
    required this.tag,
  });

  final WorkoutExerciseData we;
  final ExerciseCatalogData? exercise;
  final List<SetEntryData> sets;
  final String? tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final weightFmt = ref.watch(weightFormatProvider);
    final first = sets.firstWhereOrNull((s) => !s.isCompleted && !s.isWarmup);
    final target = first == null
        ? null
        : ref.watch(workoutTargetsProvider(we.id)).valueOrNull?[first.id];
    final kg = first == null
        ? null
        : first.weightKg > 0
        ? first.weightKg
        : target?.weightKg;
    final reps = first == null
        ? null
        : first.reps > 0
        ? first.reps
        : target?.reps;
    final working = sets.where((s) => !s.isWarmup).length;
    final detail = [
      '$working ${working == 1 ? 'set' : 'sets'}',
      if (kg != null && kg > 0 && reps != null)
        '${weightFmt.format(kg)} × $reps'
      else if (reps != null && reps > 0)
        '$reps reps',
      if (exercise != null)
        equipmentVariantLabel(we.equipmentVariant ?? exercise!.modality),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hx.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hx.primary.withValues(alpha: 0.14),
              borderRadius: HxRadius.mdAll,
            ),
            child: Icon(
              Icons.fitness_center_rounded,
              size: 26,
              color: hx.primaryText,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag == null ? 'UP NEXT' : 'UP NEXT · SUPERSET $tag',
                  style: workoutKicker(
                    context,
                    color: hx.primaryText,
                    size: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  exercise?.name ?? 'Next exercise',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(fontSize: 19),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hx.secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

/// A filled circle that pops in, with two rings rippling out behind it.
class _DoneBadge extends StatefulWidget {
  const _DoneBadge({
    super.key,
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  State<_DoneBadge> createState() => _DoneBadgeState();
}

class _DoneBadgeState extends State<_DoneBadge> with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _ripple.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: AnimatedBuilder(
        animation: _ripple,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (final delay in const [0.0, 0.16])
              Builder(
                builder: (_) {
                  final t = (_ripple.value - delay) % 1.0;
                  final eased = Curves.easeOut.transform(t);
                  return Opacity(
                    opacity: 0.55 * (1 - eased),
                    child: Transform.scale(
                      scale: 0.6 + 1.3 * eased,
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: widget.color, width: 2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            child!,
          ],
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(widget.icon, size: 50, color: widget.iconColor),
          ),
        ),
      ),
    );
  }
}
