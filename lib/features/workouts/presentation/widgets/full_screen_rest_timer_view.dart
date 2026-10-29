import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workout_target_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';
import 'package:herculex/features/workouts/domain/superset_tags.dart';
import 'package:herculex/features/workouts/presentation/widgets/fullscreen_workout_kit.dart';

part 'full_screen_rest_timer_view/_pieces.part.dart';

/// Full-screen countdown between sets: a big ring, quick adjustments, what
/// comes next, and the effort of the set just done.
///
/// [restDone] keeps the screen up after the countdown ran out, turned green,
/// until the lifter taps "Start next set".
class FullScreenRestTimerView extends ConsumerWidget {
  final WorkoutSessionData session;
  final RestTimerState restTimer;
  final bool restDone;
  final ExerciseCatalogData? currentExercise;
  final WorkoutExerciseData currentWe;
  final List<WorkoutExerciseData> exercises;
  final List<SetEntryData> currentSets;

  /// The set the rest follows, read fresh so a just-saved RPE shows.
  final SetEntryData? lastCompletedSet;
  final ExerciseCatalogData? lastCompletedExercise;

  /// `set 3` / `warm-up 1` — where [lastCompletedSet] sits in its exercise.
  final String? lastCompletedSetLabel;
  final VoidCallback onMinimize;
  final VoidCallback onStartNext;
  final Future<void> Function(SetEntryData set) onOpenRpe;
  final VoidCallback? onFinishWorkout;

  const FullScreenRestTimerView({
    super.key,
    required this.session,
    required this.restTimer,
    this.restDone = false,
    required this.currentExercise,
    required this.currentWe,
    required this.exercises,
    required this.currentSets,
    this.lastCompletedSet,
    this.lastCompletedExercise,
    this.lastCompletedSetLabel,
    required this.onMinimize,
    required this.onStartNext,
    required this.onOpenRpe,
    this.onFinishWorkout,
  });

  /// `1:04` — minutes are not padded, matching the workout header.
  static String format(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final now = ref.watch(clockProvider).now();
    final remaining = restDone ? 0 : restTimer.remainingSecondsFrom(now);
    final target = restTimer.targetSeconds;
    final timeUp = restDone || (restTimer.isRunning && remaining <= 0);
    final ringColor = timeUp ? hx.success : hx.primary;

    final upNext = _upNext(context, ref);

    return Scaffold(
      backgroundColor: hx.background,
      body: Stack(
        children: [
          Positioned(
            left: -80,
            right: -80,
            top: 40,
            height: 480,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: HxMotion.base,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      ringColor.withValues(alpha: 0.22),
                      ringColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── REST · elapsed · back to the workout ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: hx.primary.withValues(alpha: 0.12),
                          borderRadius: HxRadius.pillAll,
                          border: Border.all(
                            color: hx.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.self_improvement_rounded,
                              size: 15,
                              color: hx.primaryText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'REST',
                              style: workoutKicker(
                                context,
                                color: hx.primaryText,
                                spacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      WorkoutElapsedText(
                        startedAt: session.startedAt,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.displaySmall?.fontFamily,
                          color: hx.secondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: hx.surfaceContainer,
                        shape: StadiumBorder(
                          side: BorderSide(color: hx.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Haptics.selection();
                            onMinimize();
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 9, 14, 9),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 22,
                                  color: hx.onSurface,
                                ),
                                Text(
                                  'Workout',
                                  style: TextStyle(
                                    color: hx.onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Ring + adjustments ──
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final ring = (constraints.maxHeight - 90).clamp(
                        160.0,
                        280.0,
                      );
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Column(
                            children: [
                              _RestRing(
                                size: ring,
                                fraction: target <= 0
                                    ? 0
                                    : (remaining / target).clamp(0.0, 1.0),
                                color: ringColor,
                                label: timeUp ? 'REST DONE · GO' : 'RESTING',
                                time: format(remaining),
                                caption: target > 0
                                    ? 'of ${format(target)}'
                                    : null,
                              ),
                              const SizedBox(height: 22),
                              if (!timeUp)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _AdjustButton(
                                      label: '−15s',
                                      onTap: remaining > 15
                                          ? () => ref
                                                .read(
                                                  restTimerProvider.notifier,
                                                )
                                                .addSeconds(-15)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    _AdjustButton(
                                      label: '+30s',
                                      accent: true,
                                      onTap: () => ref
                                          .read(restTimerProvider.notifier)
                                          .addSeconds(30),
                                    ),
                                    const SizedBox(width: 8),
                                    _AdjustButton(
                                      label: '+1m',
                                      onTap: () => ref
                                          .read(restTimerProvider.notifier)
                                          .addSeconds(60),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Up next + last set's effort ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      upNext,
                      if (lastCompletedSet != null) ...[
                        const SizedBox(height: 8),
                        _LastEffortRow(
                          set: lastCompletedSet!,
                          exerciseName: lastCompletedExercise?.name,
                          setLabel: lastCompletedSetLabel,
                          onTap: () {
                            Haptics.selection();
                            onOpenRpe(lastCompletedSet!);
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: _isWorkoutComplete && onFinishWorkout != null
                      ? WorkoutHeroButton(
                          label: 'Finish workout',
                          trailingIcon: Icons.emoji_events_rounded,
                          color: hx.success,
                          foreground: successInk,
                          onPressed: () {
                            Haptics.medium();
                            ref.read(restTimerProvider.notifier).cancel();
                            onFinishWorkout!();
                          },
                        )
                      : WorkoutHeroButton(
                          label: 'Start next set',
                          leadingIcon: Icons.play_arrow_rounded,
                          color: timeUp ? hx.success : null,
                          onPressed: () {
                            Haptics.medium();
                            ref.read(restTimerProvider.notifier).cancel();
                            onStartNext();
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

  bool get _isWorkoutComplete =>
      !currentSets.any((s) => !s.isCompleted) && _nextExercise == null;

  WorkoutExerciseData? get _nextExercise {
    final i = exercises.indexWhere((e) => e.id == currentWe.id);
    return i >= 0 && i < exercises.length - 1 ? exercises[i + 1] : null;
  }

  Widget _upNext(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final weightFmt = ref.watch(weightFormatProvider);
    final nextSet = currentSets.firstWhereOrNull((s) => !s.isCompleted);

    String label;
    String name;
    String equipment = '';
    String detail = '';
    String? tag;

    if (nextSet != null) {
      final switched =
          lastCompletedSet != null &&
          lastCompletedSet!.workoutExerciseId != currentWe.id;
      final number = numberSets(currentSets)[currentSets.indexOf(nextSet)];
      label = switched
          ? (currentWe.supersetGroup != null
                ? 'UP NEXT · SUPERSET'
                : 'UP NEXT · NEXT EXERCISE')
          : number.isWarmup
          ? 'UP NEXT · WARM-UP ${number.ordinal}'
          : 'UP NEXT · SET ${number.ordinal} OF ${number.ofKind}';
      if (switched) tag = supersetTags(exercises)[currentWe.id];
      name = currentExercise?.name ?? 'Exercise';
      equipment = equipmentVariantLabel(
        currentWe.equipmentVariant ?? currentExercise?.modality ?? 'barbell',
      );
      final t = ref
          .watch(workoutTargetsProvider(currentWe.id))
          .valueOrNull?[nextSet.id];
      final kg = nextSet.weightKg > 0 ? nextSet.weightKg : t?.weightKg;
      final reps = nextSet.reps > 0 ? nextSet.reps : t?.reps;
      detail = [
        if (kg != null && kg > 0) weightFmt.formatValue(kg),
        if (reps != null && reps > 0) '$reps',
      ].join(' × ');
    } else if (_nextExercise case final next?) {
      final catalog =
          ref
              .watch(exerciseCatalogProvider(const ExerciseCatalogFilter()))
              .asData
              ?.value ??
          const <ExerciseCatalogData>[];
      final ex = catalog.firstWhereOrNull((e) => e.id == next.exerciseId);
      label = 'UP NEXT · NEXT EXERCISE';
      name = ex?.name ?? 'Next exercise';
      equipment = ex == null
          ? ''
          : equipmentVariantLabel(next.equipmentVariant ?? ex.modality);
    } else {
      label = 'ALL SETS DONE';
      name = 'Finish when ready';
    }

    final display = Theme.of(context).textTheme.displaySmall;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hx.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: workoutKicker(
                  context,
                  color: hx.primaryText,
                  size: 10.5,
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                _SupersetTag(tag: tag),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  equipment,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: hx.secondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: display?.copyWith(fontSize: 21, height: 1.15),
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  detail,
                  style: display?.copyWith(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: hx.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
