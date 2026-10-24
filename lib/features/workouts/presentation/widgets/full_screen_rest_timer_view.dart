import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workout_target_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';

/// Full-screen countdown view for rest periods during live workouts.
class FullScreenRestTimerView extends ConsumerWidget {
  final WorkoutSessionData session;
  final RestTimerState restTimer;
  final ExerciseCatalogData? currentExercise;
  final WorkoutExerciseData currentWe;
  final List<WorkoutExerciseData> exercises;
  final List<SetEntryData> currentSets;
  final int activeSetIndex;
  final SetEntryData? lastCompletedSet;
  final VoidCallback onMinimize;
  final Future<void> Function(SetEntryData set) onOpenRpe;
  final VoidCallback? onFinishWorkout;

  const FullScreenRestTimerView({
    super.key,
    required this.session,
    required this.restTimer,
    required this.currentExercise,
    required this.currentWe,
    required this.exercises,
    required this.currentSets,
    required this.activeSetIndex,
    this.lastCompletedSet,
    required this.onMinimize,
    required this.onOpenRpe,
    this.onFinishWorkout,
  });

  String _fmtSeconds(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider).now();
    final remaining = restTimer.remainingSecondsFrom(now);
    final progress = restTimer.progressFrom(now).clamp(0.0, 1.0);
    final weightFmt = ref.watch(weightFormatProvider);

    // Identify next set / exercise details for "Up Next" preview
    final nextUncompletedSet = currentSets.firstWhereOrNull(
      (s) => !s.isCompleted,
    );
    final bool hasUpcomingSetInSameEx = nextUncompletedSet != null;

    final catalog =
        ref
            .watch(exerciseCatalogProvider(const ExerciseCatalogFilter()))
            .asData
            ?.value ??
        const [];

    WorkoutExerciseData? nextExerciseWe;
    ExerciseCatalogData? nextExerciseCatalog;
    if (!hasUpcomingSetInSameEx) {
      final currentExIdx = exercises.indexWhere((e) => e.id == currentWe.id);
      if (currentExIdx >= 0 && currentExIdx < exercises.length - 1) {
        nextExerciseWe = exercises[currentExIdx + 1];
        nextExerciseCatalog = catalog.firstWhereOrNull(
          (e) => e.id == nextExerciseWe?.exerciseId,
        );
      }
    }

    final bool isWorkoutComplete =
        !hasUpcomingSetInSameEx && nextExerciseWe == null;

    // Set numbers
    final setNumbers = numberSets(currentSets);
    final nextSetNumber = nextUncompletedSet != null
        ? setNumbers[currentSets.indexOf(nextUncompletedSet)]
        : null;

    final targets = ref.watch(workoutTargetsProvider(currentWe.id)).valueOrNull;
    final nextTarget = (nextUncompletedSet != null && targets != null)
        ? targets[nextUncompletedSet.id]
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Navigation / Control Bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: AppColors.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'REST COUNTDOWN',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Minimize button to return to workout overview
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainer,
                      foregroundColor: AppColors.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                    ),
                    label: const Text(
                      'Workout',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () {
                      Haptics.selection();
                      onMinimize();
                    },
                  ),
                ],
              ),
            ),

            // ── Flexible Adaptive Center Layout ──
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;
                  final isCompact = availableHeight < 560;
                  final circleSize = isCompact
                      ? 180.0
                      : (availableHeight < 680 ? 210.0 : 230.0);
                  final trackSize = circleSize - 10.0;
                  final strokeWidth = isCompact ? 8.0 : 10.0;
                  final timerFontSize = isCompact
                      ? 48.0
                      : (availableHeight < 680 ? 56.0 : 64.0);

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: availableHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const SizedBox(height: 4),

                            // ── Hero Circular Countdown Display ──
                            Center(
                              child: SizedBox(
                                width: circleSize,
                                height: circleSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer Circular Track
                                    SizedBox(
                                      width: trackSize,
                                      height: trackSize,
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: strokeWidth,
                                        strokeCap: StrokeCap.round,
                                        backgroundColor: AppColors
                                            .outlineVariant
                                            .withValues(alpha: 0.2),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primary,
                                            ),
                                      ),
                                    ),
                                    // Centered Text Details
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            restTimer.exerciseName != null
                                                ? restTimer.exerciseName!
                                                      .toUpperCase()
                                                : 'RESTING',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: AppColors.secondary,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                  fontSize: isCompact ? 10 : 11,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              _fmtSeconds(remaining),
                                              style: theme
                                                  .textTheme
                                                  .displayLarge
                                                  ?.copyWith(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: timerFontSize,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                    letterSpacing: -1.5,
                                                    height: 1.0,
                                                  ),
                                            ),
                                          ),
                                          if (restTimer.targetSeconds > 0) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    AppColors.surfaceContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'of ${_fmtSeconds(restTimer.targetSeconds)} target',
                                                style: TextStyle(
                                                  color: AppColors.secondary,
                                                  fontSize: isCompact ? 11 : 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ── Quick Adjustment Buttons (-15s, +30s, +60s) ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: remaining > 15
                                        ? AppColors.surfaceContainer
                                        : AppColors.surfaceContainer.withValues(
                                            alpha: 0.4,
                                          ),
                                    foregroundColor: remaining > 15
                                        ? AppColors.secondary
                                        : AppColors.secondary.withValues(
                                            alpha: 0.3,
                                          ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: remaining > 15
                                      ? () {
                                          Haptics.light();
                                          ref
                                              .read(restTimerProvider.notifier)
                                              .addSeconds(-15);
                                        }
                                      : null,
                                  child: const Text(
                                    '-15s',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.18),
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    Haptics.light();
                                    ref
                                        .read(restTimerProvider.notifier)
                                        .addSeconds(30);
                                  },
                                  child: const Text(
                                    '+30s',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.surfaceContainer,
                                    foregroundColor: AppColors.secondary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    Haptics.light();
                                    ref
                                        .read(restTimerProvider.notifier)
                                        .addSeconds(60);
                                  },
                                  child: const Text(
                                    '+1m',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // ── Up Next Preview Card ──
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isWorkoutComplete
                                      ? AppColors.primary.withValues(
                                          alpha: 0.35,
                                        )
                                      : AppColors.outlineVariant.withValues(
                                          alpha: 0.3,
                                        ),
                                ),
                              ),
                              child: isWorkoutComplete
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'WORKOUT FINISHED 🏆',
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'All Exercises Completed!',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Great session! Rest up or finish now.',
                                          style: TextStyle(
                                            color: AppColors.secondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                hasUpcomingSetInSameEx
                                                    ? (nextSetNumber
                                                                  ?.isWarmup ==
                                                              true
                                                          ? 'UP NEXT • WARMUP'
                                                          : 'UP NEXT • SET ${nextSetNumber?.ordinal ?? 1}')
                                                    : 'UP NEXT • NEXT EXERCISE',
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            if (nextUncompletedSet != null)
                                              Text(
                                                equipmentVariantLabel(
                                                  currentWe.equipmentVariant ??
                                                      currentExercise
                                                          ?.modality ??
                                                      'barbell',
                                                ),
                                                style: TextStyle(
                                                  color: AppColors.secondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          hasUpcomingSetInSameEx
                                              ? (currentExercise?.name ??
                                                    'Exercise')
                                              : (nextExerciseCatalog?.name ??
                                                    'Next Exercise'),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        if (nextUncompletedSet != null) ...[
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.fitness_center_rounded,
                                                size: 15,
                                                color: AppColors.secondary,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                nextUncompletedSet.weightKg >
                                                            0 ||
                                                        nextTarget?.weightKg !=
                                                            null
                                                    ? '${weightFmt.formatValue(nextUncompletedSet.weightKg > 0 ? nextUncompletedSet.weightKg : (nextTarget?.weightKg ?? 0))} × ${nextUncompletedSet.reps > 0 ? nextUncompletedSet.reps : (nextTarget?.reps ?? 0)} reps'
                                                    : '${nextUncompletedSet.reps > 0 ? nextUncompletedSet.reps : (nextTarget?.reps ?? 0)} reps',
                                                style: TextStyle(
                                                  color: AppColors.onSurface,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ] else if (nextExerciseCatalog !=
                                            null) ...[
                                          Text(
                                            equipmentVariantLabel(
                                              nextExerciseWe
                                                      ?.equipmentVariant ??
                                                  nextExerciseCatalog.modality,
                                            ),
                                            style: TextStyle(
                                              color: AppColors.secondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),

                            // ── Last Set RPE Status / Prompt ──
                            if (lastCompletedSet != null)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Haptics.selection();
                                    onOpenRpe(lastCompletedSet!);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: lastCompletedSet!.rpeX10 != null
                                          ? Colors.purple.withValues(
                                              alpha: 0.12,
                                            )
                                          : AppColors.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: lastCompletedSet!.rpeX10 != null
                                            ? Colors.purple.withValues(
                                                alpha: 0.35,
                                              )
                                            : AppColors.outlineVariant
                                                  .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          lastCompletedSet!.rpeX10 != null
                                              ? Icons.check_circle_rounded
                                              : Icons.star_border_rounded,
                                          color:
                                              lastCompletedSet!.rpeX10 != null
                                              ? Colors.purple
                                              : AppColors.secondary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            lastCompletedSet!.rpeX10 != null
                                                ? 'Set effort logged: RPE ${(lastCompletedSet!.rpeX10! / 10).toStringAsFixed(1)}'
                                                : 'Rate effort for completed set (RPE)',
                                            style: TextStyle(
                                              color:
                                                  lastCompletedSet!.rpeX10 !=
                                                      null
                                                  ? Colors.purple
                                                  : AppColors.secondary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          lastCompletedSet!.rpeX10 != null
                                              ? 'Edit'
                                              : 'Rate',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Bottom Action: Start Next Set / Finish Workout ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: Icon(
                    isWorkoutComplete
                        ? Icons.emoji_events_rounded
                        : Icons.play_arrow_rounded,
                    size: 26,
                  ),
                  label: Text(
                    isWorkoutComplete ? 'FINISH WORKOUT 🏆' : 'START NEXT SET',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  onPressed: () {
                    Haptics.medium();
                    ref.read(restTimerProvider.notifier).cancel();
                    if (isWorkoutComplete && onFinishWorkout != null) {
                      onFinishWorkout!();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
