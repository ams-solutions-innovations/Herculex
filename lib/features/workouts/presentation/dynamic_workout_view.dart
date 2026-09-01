import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/gamification/presentation/gamification_providers.dart';
import 'package:herculex/features/workouts/application/finish_workout_action.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/set_type_meta.dart';
import 'package:herculex/features/workouts/presentation/rest_timer_controller.dart';
import 'package:herculex/features/workouts/presentation/workout_finish_view.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';

/// Dynamic workout mode (§14): full-screen, distraction-free view with
/// horizontal exercise swipe, automated active set & exercise tracking,
/// clean bold typography, and continuous watch-style digital crown drag wheels.
class DynamicWorkoutView extends ConsumerStatefulWidget {
  final WorkoutSessionData session;
  const DynamicWorkoutView({super.key, required this.session});

  @override
  ConsumerState<DynamicWorkoutView> createState() => _DynamicWorkoutViewState();
}

class _DynamicWorkoutViewState extends ConsumerState<DynamicWorkoutView> {
  late PageController _pageController;
  int _exerciseIndex = 0;
  bool _hasAutoSelectedInitialExercise = false;

  // Track user-selected set index override per exercise ID (if user manually taps a set dot)
  final Map<int, int> _selectedSetIndexByExercise = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _exerciseIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Dynamic mode used to open [WorkoutFinishView] without ever calling
  /// `endSession`, so the session stayed active: the summary reported a `0m`
  /// duration and fell back to the `sets.length * 2` calorie estimate, while
  /// the live banner and the ongoing-workout notification kept running behind
  /// the celebration screen. It now runs the same [FinishWorkoutAction] as
  /// classic mode.
  Future<void> _finishWorkout() async {
    // Resolved before the first await — `endSession` disposes this widget the
    // moment `activeSessionProvider` re-emits. See FinishWorkoutAction.
    final finish = FinishWorkoutAction.resolve(ref);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final session = widget.session;

    await finish.run(session: session);

    if (!rootNavigator.mounted) return;
    // ignore: use_build_context_synchronously
    await WorkoutFinishView.show(rootNavigator.context, session.id);
  }

  void _goToExercise(int newIndex, List<WorkoutExerciseData> exercises) {
    if (newIndex < 0 || newIndex >= exercises.length) return;
    setState(() {
      _exerciseIndex = newIndex;
    });
    if (_pageController.hasClients &&
        _pageController.page?.round() != newIndex) {
      _pageController.animateToPage(
        newIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _selectSetForExercise(int exerciseId, int setIndex) {
    setState(() {
      _selectedSetIndexByExercise[exerciseId] = setIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises =
        ref.watch(sessionExercisesProvider(widget.session.id)).asData?.value ??
        const <WorkoutExerciseData>[];
    final catalog =
        ref
            .watch(exerciseCatalogProvider(const ExerciseCatalogFilter()))
            .asData
            ?.value ??
        const [];
    final restTimer = ref.watch(restTimerProvider);

    // Auto-focus the first exercise with incomplete sets on initial load
    if (!_hasAutoSelectedInitialExercise && exercises.isNotEmpty) {
      _hasAutoSelectedInitialExercise = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        int targetIdx = -1;
        for (int i = 0; i < exercises.length; i++) {
          final sets =
              ref
                  .read(setsForWorkoutExerciseProvider(exercises[i].id))
                  .asData
                  ?.value ??
              [];
          final hasIncomplete = sets.any((s) => !s.isCompleted);
          if (hasIncomplete) {
            targetIdx = i;
            break;
          }
        }
        if (targetIdx >= 0 && targetIdx != _exerciseIndex) {
          _goToExercise(targetIdx, exercises);
        }
      });
    }

    if (_exerciseIndex >= exercises.length && exercises.isNotEmpty) {
      _exerciseIndex = exercises.length - 1;
    }

    if (exercises.isEmpty) {
      return SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit),
                  tooltip: 'Exit fullscreen',
                  onPressed: () =>
                      ref.read(dynamicWorkoutModeProvider.notifier).state =
                          false,
                ),
                const Spacer(),
              ],
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Add exercises in Classic mode',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final currentWe = exercises[_exerciseIndex];
    final currentExercise = catalog.firstWhereOrNull(
      (e) => e.id == currentWe.exerciseId,
    );
    final currentSets =
        ref.watch(setsForWorkoutExerciseProvider(currentWe.id)).asData?.value ??
        const <SetEntryData>[];

    // Determine currently focused set for current exercise
    final manualSetIdx = _selectedSetIndexByExercise[currentWe.id];
    final nextUncompletedIdx = currentSets.indexWhere((s) => !s.isCompleted);
    final effectiveSetIdx =
        manualSetIdx != null && manualSetIdx < currentSets.length
        ? manualSetIdx
        : (nextUncompletedIdx >= 0
              ? nextUncompletedIdx
              : (currentSets.isNotEmpty ? currentSets.length - 1 : 0));

    final activeSet = currentSets.elementAtOrNull(effectiveSetIdx);
    final isSuperset = currentWe.supersetGroup != null;
    final linkedCount = isSuperset
        ? exercises
              .where((e) => e.supersetGroup == currentWe.supersetGroup)
              .length
        : 0;
    final linkedLabel = linkedCount == 2
        ? 'SUPERSET'
        : (linkedCount == 3 ? 'TRI-SET' : 'GIANT SET');

    return SafeArea(
      child: Column(
        children: [
          // ── Top Header: Exit Fullscreen + Exercise Index & Superset indicator ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit, size: 28),
                  tooltip: 'Classic mode',
                  onPressed: () =>
                      ref.read(dynamicWorkoutModeProvider.notifier).state =
                          false,
                ),
                const Spacer(),
                if (isSuperset) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26C6DA).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF26C6DA),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.link,
                          size: 14,
                          color: Color(0xFF26C6DA),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          linkedLabel,
                          style: const TextStyle(
                            color: Color(0xFF26C6DA),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${_exerciseIndex + 1}/${exercises.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // ── Central Body: PageView for horizontal exercise swiping ──
          Expanded(
            child: restTimer.isRunning
                ? _buildRestTimerDisplay(context, restTimer)
                : PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) {
                      setState(() {
                        _exerciseIndex = idx;
                      });
                    },
                    itemCount: exercises.length,
                    itemBuilder: (context, exIdx) {
                      final we = exercises[exIdx];
                      final catalogEx = catalog.firstWhereOrNull(
                        (e) => e.id == we.exerciseId,
                      );
                      final sets =
                          ref
                              .watch(setsForWorkoutExerciseProvider(we.id))
                              .asData
                              ?.value ??
                          const <SetEntryData>[];
                      final setIdxForThisEx =
                          _selectedSetIndexByExercise[we.id];
                      final nextUncomp = sets.indexWhere((s) => !s.isCompleted);
                      final activeIdx =
                          setIdxForThisEx != null &&
                              setIdxForThisEx < sets.length
                          ? setIdxForThisEx
                          : (nextUncomp >= 0
                                ? nextUncomp
                                : (sets.isNotEmpty ? sets.length - 1 : 0));
                      final selectedSet = sets.elementAtOrNull(activeIdx);

                      return _buildExerciseScreen(
                        context,
                        we: we,
                        catalogExercise: catalogEx,
                        sets: sets,
                        activeSet: selectedSet,
                        activeSetIndex: activeIdx,
                      );
                    },
                  ),
          ),

          // ── Bottom Action Area: Complete Set / Skip Rest / Next Exercise ──
          _buildActionArea(
            context,
            exercises: exercises,
            currentWe: currentWe,
            currentExercise: currentExercise,
            currentSets: currentSets,
            activeSet: activeSet,
            restTimer: restTimer,
          ),

          // ── Bottom Navigation Bar: Exercise stepping < > ──
          _buildBottomExerciseNav(context, exercises),
        ],
      ),
    );
  }

  /// Big Rest Timer Screen
  Widget _buildRestTimerDisplay(
    BuildContext context,
    RestTimerState restTimer,
  ) {
    final theme = Theme.of(context);
    final remaining = restTimer.remainingSecondsFrom(DateTime.now());
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'REST',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _fmtSeconds(remaining),
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 88,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.0,
            ),
          ),
          if (restTimer.exerciseName != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                restTimer.exerciseName!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Full exercise screen for a given exercise in the PageView
  Widget _buildExerciseScreen(
    BuildContext context, {
    required WorkoutExerciseData we,
    required ExerciseCatalogData? catalogExercise,
    required List<SetEntryData> sets,
    required SetEntryData? activeSet,
    required int activeSetIndex,
  }) {
    final theme = Theme.of(context);
    final metric = catalogExercise != null
        ? effectiveLoggingMetric(
            exercise: catalogExercise,
            equipmentVariant: we.equipmentVariant,
          )
        : LoggingMetric.weightReps;

    final weightFmt = ref.watch(weightFormatProvider);
    final allDone = sets.isNotEmpty && sets.every((s) => s.isCompleted);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // Exercise Name
          if (catalogExercise != null) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.selection();
                context.push('/exercise/${catalogExercise.id}');
              },
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      catalogExercise.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    equipmentVariantLabel(
                      we.equipmentVariant ?? catalogExercise.modality,
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          if (sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No sets added for this exercise',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            )
          else ...[
            // Set Badge & Number (e.g. SET 2/4)
            if (activeSet != null) ...[
              _buildSetHeaderBadge(
                context,
                set: activeSet,
                setIndex: activeSetIndex + 1,
                totalSets: sets.length,
              ),
              const SizedBox(height: 12),
            ],

            // Interactive Set Dots / Selector Bar
            if (sets.length > 1) ...[
              _buildSetDotsBar(
                context,
                exerciseId: we.id,
                sets: sets,
                activeSetIndex: activeSetIndex,
              ),
              const SizedBox(height: 16),
            ],

            // If active set exists, display the interactive watch-style wheels
            if (activeSet != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Weight Column
                  if (metric.has(SetField.weight))
                    _WatchCrownNumberWheel(
                      key: ValueKey('w_${activeSet.id}_${activeSet.weightKg}'),
                      label: weightFmt.suffix.toUpperCase(),
                      value: activeSet.weightKg,
                      step: 0.5,
                      min: 0.0,
                      max: 999.0,
                      displayFormatter: (val) => weightFmt.formatValue(val),
                      onChanged: (newWeight) async {
                        await ref
                            .read(workoutsRepositoryProvider)
                            .updateSet(
                              setId: activeSet.id,
                              weightKg: newWeight.clamp(0.0, 999.0),
                            );
                      },
                    ),

                  // Divider between metrics
                  if (metric.has(SetField.weight) && metric.isRepBased)
                    Container(
                      height: 70,
                      width: 1,
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),

                  // Reps Column
                  if (metric.isRepBased)
                    _WatchCrownNumberWheel(
                      key: ValueKey('r_${activeSet.id}_${activeSet.reps}'),
                      label: 'REPS',
                      value: activeSet.reps.toDouble(),
                      step: 1.0,
                      min: 1.0,
                      max: 999.0,
                      isInteger: true,
                      displayFormatter: (val) => val.toInt().toString(),
                      onChanged: (newReps) async {
                        await ref
                            .read(workoutsRepositoryProvider)
                            .updateSet(
                              setId: activeSet.id,
                              reps: newReps.toInt().clamp(1, 999),
                            );
                      },
                    ),

                  // Duration for timed metrics
                  if (metric.has(SetField.duration))
                    _WatchCrownNumberWheel(
                      key: ValueKey(
                        'd_${activeSet.id}_${activeSet.durationSeconds}',
                      ),
                      label: 'SEC',
                      value: (activeSet.durationSeconds ?? 30).toDouble(),
                      step: 5.0,
                      min: 1.0,
                      max: 3600.0,
                      isInteger: true,
                      displayFormatter: (val) => val.toInt().toString(),
                      onChanged: (newSec) async {
                        await ref
                            .read(workoutsRepositoryProvider)
                            .updateSet(
                              setId: activeSet.id,
                              durationSeconds: newSec.toInt().clamp(1, 3600),
                            );
                      },
                    ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                'Drag continuously up/down or tap to type',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 12),

              // Extra Reps Chips (Forced / Cheat / Myo)
              _buildExtraRepsSection(context, set: activeSet),

              const SizedBox(height: 8),

              // Accessories / Bands Pills
              _DynamicSetAccessoryPills(setId: activeSet.id),
            ],

            if (allDone) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'All sets done 🎉',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Header badge for the set (e.g. WARMUP • SET 1/4 or SET 2/3)
  Widget _buildSetHeaderBadge(
    BuildContext context, {
    required SetEntryData set,
    required int setIndex,
    required int totalSets,
  }) {
    final setType = SetType.fromId(set.setType);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: set.isCompleted
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: set.isCompleted
                  ? AppColors.primary
                  : AppColors.outlineVariant.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (set.isWarmup) ...[
                const Icon(
                  Icons.local_fire_department,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
                const Text(
                  'WARMUP • ',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ] else if (setType != SetType.standard) ...[
                Text(
                  '${setType.label.toUpperCase()} • ',
                  style: TextStyle(
                    color: _colorForSetType(setType),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
              Text(
                'SET $setIndex/$totalSets',
                style: TextStyle(
                  color: set.isCompleted
                      ? AppColors.primary
                      : AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              if (set.isCompleted) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle, size: 16, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Sleek horizontal set dots selector bar
  Widget _buildSetDotsBar(
    BuildContext context, {
    required int exerciseId,
    required List<SetEntryData> sets,
    required int activeSetIndex,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(sets.length, (idx) {
          final isSelected = idx == activeSetIndex;
          final isDone = sets[idx].isCompleted;
          return GestureDetector(
            onTap: () {
              Haptics.selection();
              _selectSetForExercise(exerciseId, idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDone ? AppColors.primary : AppColors.primaryContainer)
                    : (isDone
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.surfaceContainerLowest),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDone
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : AppColors.outlineVariant.withValues(alpha: 0.3)),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDone) ...[
                    Icon(
                      Icons.check,
                      size: 13,
                      color: isSelected ? Colors.black : AppColors.primary,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '${idx + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected
                          ? (isDone
                                ? Colors.black
                                : theme.colorScheme.onPrimaryContainer)
                          : (isDone
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Extra Reps Section for Myo / Forced / Cheat reps
  Widget _buildExtraRepsSection(
    BuildContext context, {
    required SetEntryData set,
  }) {
    final setType = SetType.fromId(set.setType);
    if (setType != SetType.myoReps &&
        setType != SetType.forced &&
        setType != SetType.cheat) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final meta = decodeSetTypeMeta(set.setTypeMetaJson);

    final List<int> extraItems;
    final String metaKey;
    final String buttonLabel;
    final String chipSuffix;
    final Color accentColor;

    if (setType == SetType.myoReps) {
      metaKey = 'miniSets';
      buttonLabel = 'Mini-Set';
      chipSuffix = 'reps';
      accentColor = AppColors.primary;
      extraItems = setTypeMetaInts(meta['miniSets']);
    } else if (setType == SetType.forced) {
      metaKey = 'extraReps';
      buttonLabel = 'Forced';
      chipSuffix = 'forced';
      accentColor = const Color(0xFFE53935);
      extraItems = setTypeMetaInts(meta['extraReps'] ?? meta['forcedReps']);
    } else {
      metaKey = 'extraReps';
      buttonLabel = 'Cheat';
      chipSuffix = 'cheat';
      accentColor = const Color(0xFFFF7043);
      extraItems = setTypeMetaInts(meta['extraReps'] ?? meta['cheatReps']);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                setType == SetType.myoReps
                    ? 'MYO MINI-SETS'
                    : (setType == SetType.forced
                          ? 'FORCED REPS'
                          : 'CHEAT REPS'),
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < extraItems.length; i++)
                InkWell(
                  onTap: () async {
                    final newItems = List<int>.from(extraItems)..removeAt(i);
                    meta[metaKey] = newItems;
                    await ref
                        .read(workoutsRepositoryProvider)
                        .updateSet(
                          setId: set.id,
                          setTypeMetaJson: jsonEncode(meta),
                        );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${extraItems[i]} $chipSuffix',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                onTap: () async {
                  final reps = await _askForExtraReps(
                    context,
                    title: setType == SetType.myoReps
                        ? 'Add Mini-Set'
                        : (setType == SetType.forced
                              ? 'Add forced reps'
                              : 'Add cheat reps'),
                    hint: 'Number of extra reps (e.g. 2)',
                  );
                  if (reps != null && reps > 0) {
                    final newItems = List<int>.from(extraItems)..add(reps);
                    meta[metaKey] = newItems;
                    await ref
                        .read(workoutsRepositoryProvider)
                        .updateSet(
                          setId: set.id,
                          setTypeMetaJson: jsonEncode(meta),
                        );
                    if (setType == SetType.myoReps) {
                      ref
                          .read(restTimerProvider.notifier)
                          .start(seconds: 15, exerciseName: 'Myo-rep Rest');
                    }
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: accentColor),
                      const SizedBox(width: 2),
                      Text(
                        buttonLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Big Bottom Action Area
  Widget _buildActionArea(
    BuildContext context, {
    required List<WorkoutExerciseData> exercises,
    required WorkoutExerciseData currentWe,
    required ExerciseCatalogData? currentExercise,
    required List<SetEntryData> currentSets,
    required SetEntryData? activeSet,
    required RestTimerState restTimer,
  }) {
    if (restTimer.isRunning) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: () =>
                      ref.read(restTimerProvider.notifier).cancel(),
                  child: const Text(
                    'SKIP REST',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: () =>
                      ref.read(restTimerProvider.notifier).addSeconds(30),
                  child: const Text(
                    '+30s',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final targetSet =
        activeSet ?? currentSets.firstWhereOrNull((s) => !s.isCompleted);
    final allCurrentSetsCompleted =
        currentSets.isNotEmpty && currentSets.every((s) => s.isCompleted);
    final hasNextExercise = _exerciseIndex < exercises.length - 1;

    // If all sets for this exercise are finished
    if (targetSet == null || allCurrentSetsCompleted) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: hasNextExercise
                  ? AppColors.primary
                  : const Color(0xFF43A047),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            onPressed: () {
              if (hasNextExercise) {
                _goToExercise(_exerciseIndex + 1, exercises);
              } else {
                _finishWorkout();
              }
            },
            child: Text(
              hasNextExercise ? 'NEXT EXERCISE →' : 'FINISH WORKOUT 🏆',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    // Complete Set Button
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          onPressed: () async {
            Haptics.medium();
            final repo = ref.read(workoutsRepositoryProvider);
            final ex = currentExercise;
            await repo.updateSet(setId: targetSet.id, isCompleted: true);

            if (ex != null && !targetSet.isWarmup) {
              final effectiveKg =
                  targetSet.weightKg +
                  (targetSet.bodyweightKg ?? 0.0) +
                  (targetSet.chainsKg ?? 0.0);
              ref
                  .read(gamificationServiceProvider)
                  .onSetCompleted(
                    sessionId: widget.session.id,
                    exerciseId: ex.id,
                    exerciseName: ex.name,
                    primaryMuscle: ex.primaryMuscle,
                    effectiveKg: effectiveKg,
                    weightKg: targetSet.weightKg,
                    reps: targetSet.reps,
                    accessoryNames: const [],
                    equipmentVariant: currentWe.equipmentVariant ?? ex.modality,
                    setType: SetType.fromId(targetSet.setType),
                  );
            }

            // Clear any manual set override for this exercise so it moves forward
            _selectedSetIndexByExercise.remove(currentWe.id);

            // Progression & rest timer logic
            if (currentWe.supersetGroup != null) {
              final groupExercises = exercises
                  .where((e) => e.supersetGroup == currentWe.supersetGroup)
                  .toList();
              if (groupExercises.length > 1) {
                final currentPosInGroup = groupExercises.indexWhere(
                  (e) => e.id == currentWe.id,
                );
                final isLastInRound =
                    currentPosInGroup == groupExercises.length - 1;

                if (isLastInRound) {
                  final restSec =
                      currentWe.targetRestSeconds ??
                      (ex?.defaultRestSeconds ?? 90);
                  ref
                      .read(restTimerProvider.notifier)
                      .start(
                        seconds: restSec,
                        exerciseName:
                            'Circuit Rest (Round ${targetSet.setIndex})',
                      );
                }

                // Look for the next exercise in the superset with incomplete sets
                bool foundNextInSuperset = false;
                for (int step = 1; step <= groupExercises.length; step++) {
                  final candidateEx =
                      groupExercises[(currentPosInGroup + step) %
                          groupExercises.length];
                  final candidateSets = await repo
                      .watchSetsForWorkoutExercise(candidateEx.id)
                      .first;
                  final nextOpenSetIdx = candidateSets.indexWhere(
                    (s) => !s.isCompleted,
                  );
                  if (nextOpenSetIdx >= 0) {
                    final candidateOverallIdx = exercises.indexWhere(
                      (e) => e.id == candidateEx.id,
                    );
                    if (candidateOverallIdx >= 0 && mounted) {
                      _goToExercise(candidateOverallIdx, exercises);
                      foundNextInSuperset = true;
                      break;
                    }
                  }
                }
                if (foundNextInSuperset) return;
              }
            } else {
              final restSec =
                  currentWe.targetRestSeconds ?? (ex?.defaultRestSeconds ?? 90);
              ref
                  .read(restTimerProvider.notifier)
                  .start(seconds: restSec, exerciseName: ex?.name);
            }

            // Normal progression: check if all sets are done for this exercise
            final remainingSets = await repo
                .watchSetsForWorkoutExercise(currentWe.id)
                .first;
            final hasPendingSets = remainingSets.any((s) => !s.isCompleted);

            if (!hasPendingSets &&
                _exerciseIndex < exercises.length - 1 &&
                mounted) {
              // Automatically navigate to next exercise if this one is done
              _goToExercise(_exerciseIndex + 1, exercises);
            }
          },
          child: Text(
            targetSet.isCompleted ? 'RE-LOG SET' : 'COMPLETE SET',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  /// Bottom exercise stepping navigation bar
  Widget _buildBottomExerciseNav(
    BuildContext context,
    List<WorkoutExerciseData> exercises,
  ) {
    final theme = Theme.of(context);
    final hasPrev = _exerciseIndex > 0;
    final hasNext = _exerciseIndex < exercises.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          // Previous Exercise Button <
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: hasPrev
                  ? AppColors.surfaceContainer
                  : AppColors.surfaceContainerLowest,
            ),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: hasPrev
                  ? AppColors.onSurface
                  : AppColors.outlineVariant.withValues(alpha: 0.4),
              size: 28,
            ),
            onPressed: hasPrev
                ? () => _goToExercise(_exerciseIndex - 1, exercises)
                : null,
          ),

          const SizedBox(width: 8),

          // Exercise Navigation Title & Indicator
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Exercise ${_exerciseIndex + 1} of ${exercises.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Swipe horizontally for exercises',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.outline,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Next Exercise Button >
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: hasNext
                  ? AppColors.surfaceContainer
                  : AppColors.surfaceContainerLowest,
            ),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: hasNext
                  ? AppColors.onSurface
                  : AppColors.outlineVariant.withValues(alpha: 0.4),
              size: 28,
            ),
            onPressed: hasNext
                ? () => _goToExercise(_exerciseIndex + 1, exercises)
                : null,
          ),
        ],
      ),
    );
  }

  Color _colorForSetType(SetType type) => switch (type) {
    SetType.drop => const Color(0xFFE57373),
    SetType.restPause => const Color(0xFFFFB74D),
    SetType.partials => const Color(0xFFFF8A65),
    SetType.myoReps => const Color(0xFF81C784),
    SetType.forced => const Color(0xFFE53935),
    SetType.cheat => const Color(0xFFFF7043),
    SetType.negatives => const Color(0xFF9575CD),
    SetType.pause => const Color(0xFF4FC3F7),
    SetType.downSets => const Color(0xFFBA68C8),
    _ => AppColors.primary,
  };

  String _fmtSeconds(int s) =>
      '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<int?> _askForExtraReps(
    BuildContext context, {
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 4, 5].map((count) {
                return ActionChip(
                  label: Text('+$count'),
                  onPressed: () => Navigator.of(ctx).pop(count),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctrl.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// Continuous Watch-Style Digital Crown Number Wheel for Weight & Reps.
/// Allows continuous finger dragging up/down without interruptions,
/// responsive 120fps local updates, haptic ticks on every notch,
/// mouse wheel scroll support, and direct tap-to-type dialog.
class _WatchCrownNumberWheel extends StatefulWidget {
  final String label;
  final double value;
  final double step;
  final double min;
  final double max;
  final bool isInteger;
  final String Function(double) displayFormatter;
  final ValueChanged<double> onChanged;

  const _WatchCrownNumberWheel({
    super.key,
    required this.label,
    required this.value,
    required this.step,
    this.min = 0.0,
    this.max = 999.0,
    this.isInteger = false,
    required this.displayFormatter,
    required this.onChanged,
  });

  @override
  State<_WatchCrownNumberWheel> createState() => _WatchCrownNumberWheelState();
}

class _WatchCrownNumberWheelState extends State<_WatchCrownNumberWheel> {
  late double _localValue;
  double _dragAccumulator = 0;
  static const double _pixelsPerStep = 13.0;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _WatchCrownNumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _localValue = widget.value;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _applyDelta(int steps) {
    if (steps == 0) return;
    Haptics.selection();

    final delta = steps * widget.step;
    var newVal = _localValue + delta;
    newVal = newVal.clamp(widget.min, widget.max);

    final rounded = widget.isInteger
        ? newVal.roundToDouble()
        : ((newVal * 10).round() / 10.0);

    setState(() {
      _localValue = rounded;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      widget.onChanged(_localValue);
    });
  }

  void _flushImmediate() {
    _debounceTimer?.cancel();
    widget.onChanged(_localValue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = widget.displayFormatter(_localValue);

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          if (pointerSignal.scrollDelta.dy < 0) {
            _applyDelta(1);
          } else if (pointerSignal.scrollDelta.dy > 0) {
            _applyDelta(-1);
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _dragAccumulator = 0;
        },
        onVerticalDragUpdate: (details) {
          // Negative dy means dragging UP -> increment value
          _dragAccumulator -= details.primaryDelta ?? 0;
          if (_dragAccumulator.abs() >= _pixelsPerStep) {
            final steps = (_dragAccumulator / _pixelsPerStep).truncate();
            _dragAccumulator -= steps * _pixelsPerStep;
            _applyDelta(steps);
          }
        },
        onVerticalDragEnd: (_) {
          _dragAccumulator = 0;
          _flushImmediate();
        },
        onVerticalDragCancel: () {
          _dragAccumulator = 0;
          _flushImmediate();
        },
        onTap: () async {
          final ctrl = TextEditingController(text: formatted);
          final entered = await showDialog<double>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Set ${widget.label}'),
              content: TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(hintText: widget.label),
                onSubmitted: (v) => Navigator.of(ctx).pop(double.tryParse(v)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(double.tryParse(ctrl.text)),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (entered != null &&
              entered >= widget.min &&
              entered <= widget.max) {
            setState(() {
              _localValue = entered;
            });
            _flushImmediate();
          }
        },
        child: Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Up crown tick arrow
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 22,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 1),
              Text(
                widget.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatted,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontSize: 50,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 1),
              // Down crown tick arrow
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accessory & Band badges attached to a specific set
class _DynamicSetAccessoryPills extends ConsumerWidget {
  final int setId;
  const _DynamicSetAccessoryPills({required this.setId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attachedAccs =
        ref.watch(setAccessoriesProvider(setId)).asData?.value ?? const [];
    final attachedBands =
        ref.watch(setBandsProvider(setId)).asData?.value ?? const [];
    final catalogAccs =
        ref.watch(accessoriesProvider).asData?.value ?? const [];
    final catalogBands = ref.watch(bandsProvider).asData?.value ?? const [];

    final activeTags = <String>[];
    for (final sa in attachedAccs) {
      final acc = catalogAccs.firstWhereOrNull((a) => a.id == sa.accessoryId);
      if (acc != null) activeTags.add(acc.name);
    }
    for (final sb in attachedBands) {
      final band = catalogBands.firstWhereOrNull((b) => b.id == sb.bandId);
      final modeStr = sb.mode == 'assistance' ? 'Ast.' : 'Res.';
      if (band != null) {
        activeTags.add('${band.name} ($modeStr)');
      } else {
        activeTags.add('Band ($modeStr)');
      }
    }

    if (activeTags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final tag in activeTags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  tag,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
