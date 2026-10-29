import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_nav_bar.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/presentation/sheets/weekly_adaptation_sheet.dart';
import 'package:herculex/features/workouts/application/finish_workout_action.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workout_target_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/workout_targets_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/set_type_meta.dart';
import 'package:herculex/features/workouts/domain/superset_tags.dart';
import 'package:herculex/features/workouts/domain/workout_target_resolver.dart';
import 'package:herculex/features/workouts/presentation/dialogs/full_screen_rpe_picker.dart';
import 'package:herculex/features/workouts/presentation/views/workout_finish_view.dart';
import 'package:herculex/features/workouts/presentation/widgets/calisthenics_progression_card.dart';
import 'package:herculex/features/workouts/presentation/widgets/full_screen_rest_timer_view.dart';
import 'package:herculex/features/workouts/presentation/widgets/fullscreen_workout_kit.dart';
import 'package:intl/intl.dart';

part 'dynamic_workout_view/_done.part.dart';
part 'dynamic_workout_view/_exercise_page.part.dart';
part 'dynamic_workout_view/_flick_picker.part.dart';
part 'dynamic_workout_view/_header.part.dart';
part 'dynamic_workout_view/_progression.part.dart';
part 'dynamic_workout_view/_set_headline.part.dart';
part 'dynamic_workout_view/_set_extras.part.dart';

/// Dynamic workout mode (§14): full-screen, distraction-free view with
/// horizontal exercise swipe, automated active set & exercise tracking,
/// clean bold typography, and continuous watch-style digital crown drag wheels.
///
/// One set at a time: complete it, rate it, rest, and the next set (or the
/// next exercise) is already on screen. Finishing an exercise, and the whole
/// workout, gets its own short "done" step before moving on.
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

  /// The set and exercise catalog data most recently completed.
  int? _lastCompletedSetId;
  SetEntryData? _lastCompletedSet;
  ExerciseCatalogData? _lastCompletedExerciseCatalog;

  /// The exercise / workout done step, when one is showing.
  _Done? _done;

  /// The rest ran out on screen and now waits for "Start next set".
  bool _restDone = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _exerciseIndex);
    // A previous session can end while a done step is up; start clean.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncInterstitial();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Hides the app's nav bar while a step outlives the rest countdown.
  void _syncInterstitial() {
    ref.read(dynamicWorkoutInterstitialProvider.notifier).state =
        _done != null || _restDone;
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
    final adaptation = ref.read(weeklyAdaptationRepositoryProvider);
    final interstitial = ref.read(dynamicWorkoutInterstitialProvider.notifier);

    await finish.run(session: session);
    interstitial.state = false;

    if (!rootNavigator.mounted) return;
    final proposal = await adaptation.proposeForIncompleteSession(session.id);
    if (proposal != null && rootNavigator.mounted) {
      await showWeeklyAdaptationSheet(
        rootNavigator.context,
        repository: adaptation,
        proposal: proposal,
        skipOnDecline: false,
      );
    }
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

  void _exitToClassic() {
    ref.read(dynamicRestTimerMinimizedProvider.notifier).state = false;
    ref.read(dynamicWorkoutInterstitialProvider.notifier).state = false;
    ref.read(dynamicWorkoutModeProvider.notifier).state = false;
  }

  /// A rest that runs out while its screen is up stays there, turned green.
  void _onRestTimerChanged(RestTimerState? prev, RestTimerState next) {
    if (next.isRunning) {
      if (_restDone) {
        setState(() => _restDone = false);
        _syncInterstitial();
      }
      return;
    }
    if (prev == null || !prev.isRunning || _done != null) return;
    if (ref.read(dynamicRestTimerMinimizedProvider)) return;
    final expired =
        prev.remainingSecondsFrom(ref.read(clockProvider).now()) <= 0;
    if (expired && mounted) {
      setState(() => _restDone = true);
      _syncInterstitial();
    }
  }

  int _activeIndexFor(int workoutExerciseId, List<SetEntryData> sets) {
    final manual = _selectedSetIndexByExercise[workoutExerciseId];
    if (manual != null && manual < sets.length) return manual;
    final open = sets.indexWhere((s) => !s.isCompleted);
    if (open >= 0) return open;
    return sets.isNotEmpty ? sets.length - 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final exercises =
        ref.watch(sessionExercisesProvider(widget.session.id)).asData?.value ??
        const <WorkoutExerciseData>[];
    final catalog =
        ref
            .watch(exerciseCatalogProvider(const ExerciseCatalogFilter()))
            .asData
            ?.value ??
        const <ExerciseCatalogData>[];
    final restTimer = ref.watch(restTimerProvider);
    ref.listen<RestTimerState>(restTimerProvider, _onRestTimerChanged);

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

    if (exercises.isEmpty) return _EmptyWorkout(onExit: _exitToClassic);

    final currentWe = exercises[_exerciseIndex];
    final currentExercise = catalog.firstWhereOrNull(
      (e) => e.id == currentWe.exerciseId,
    );
    final currentSets =
        ref.watch(setsForWorkoutExerciseProvider(currentWe.id)).asData?.value ??
        const <SetEntryData>[];
    final effectiveSetIdx = _activeIndexFor(currentWe.id, currentSets);
    final activeSet = currentSets.elementAtOrNull(effectiveSetIdx);
    final tags = supersetTags(exercises);

    // The set the current rest follows, read fresh so a saved RPE shows.
    final lastExerciseId = _lastCompletedSet?.workoutExerciseId;
    final lastSets = lastExerciseId == null
        ? currentSets
        : ref
                  .watch(setsForWorkoutExerciseProvider(lastExerciseId))
                  .asData
                  ?.value ??
              const <SetEntryData>[];
    final lastCompletedSet = _lastCompletedSetId != null
        ? lastSets.firstWhereOrNull((s) => s.id == _lastCompletedSetId) ??
              _lastCompletedSet
        : currentSets.reversed.firstWhereOrNull((s) => s.isCompleted);
    final lastIdx = lastCompletedSet == null
        ? -1
        : lastSets.indexWhere((s) => s.id == lastCompletedSet.id);

    final isRestTimerMinimized = ref.watch(dynamicRestTimerMinimizedProvider);
    if (!restTimer.isRunning && isRestTimerMinimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(dynamicRestTimerMinimizedProvider.notifier).state = false;
        }
      });
    }
    final showRest =
        _done == null &&
        ((restTimer.isRunning && !isRestTimerMinimized) || _restDone);

    return Stack(
      children: [
        Positioned(
          left: -40,
          right: -40,
          top: 300,
          height: 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    hx.primary.withValues(alpha: 0.20),
                    hx.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _WorkoutHeader(
                session: widget.session,
                exercises: exercises,
                exerciseIndex: _exerciseIndex,
                onExit: _exitToClassic,
              ),

              if (restTimer.isRunning && isRestTimerMinimized)
                _MinimizedRestPill(restTimer: restTimer),

              // ── One page per exercise; swipe sideways between them ──
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) {
                    setState(() {
                      _exerciseIndex = idx;
                    });
                  },
                  itemCount: exercises.length,
                  itemBuilder: (context, exIdx) {
                    final we = exercises[exIdx];
                    final sets =
                        ref
                            .watch(setsForWorkoutExerciseProvider(we.id))
                            .asData
                            ?.value ??
                        const <SetEntryData>[];
                    final activeIdx = _activeIndexFor(we.id, sets);
                    final catalogEx = catalog.firstWhereOrNull(
                      (e) => e.id == we.exerciseId,
                    );
                    return _ExercisePage(
                      we: we,
                      catalogExercise: catalogEx,
                      catalog: catalog,
                      exercises: exercises,
                      tags: tags,
                      sets: sets,
                      activeSet: sets.elementAtOrNull(activeIdx),
                      activeSetIndex: activeIdx,
                      onSelectSet: (i) => _selectSetForExercise(we.id, i),
                      onOpenRpe: (set, i) => _promptFullScreenRpe(
                        targetSet: set,
                        catalogExercise: catalogEx,
                        sets: sets,
                        setIndex: i,
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: _buildPrimaryAction(
                  exercises: exercises,
                  currentWe: currentWe,
                  currentExercise: currentExercise,
                  currentSets: currentSets,
                  activeSet: activeSet,
                  effectiveSetIdx: effectiveSetIdx,
                ),
              ),

              _ExerciseStepper(
                exercises: exercises,
                catalog: catalog,
                index: _exerciseIndex,
                onGo: (i) => _goToExercise(i, exercises),
              ),

              // The app's floating nav bar overlays this screen; keep the
              // Complete Set button clear of it.
              SizedBox(
                height: HxNavBar.clearanceOf(context) - HxSpace.x2 - HxSpace.x3,
              ),
            ],
          ),
        ),

        if (showRest)
          Positioned.fill(
            child: FullScreenRestTimerView(
              session: widget.session,
              restTimer: restTimer,
              restDone: _restDone,
              currentExercise: currentExercise,
              currentWe: currentWe,
              exercises: exercises,
              currentSets: currentSets,
              lastCompletedSet: lastCompletedSet,
              lastCompletedExercise:
                  _lastCompletedExerciseCatalog ?? currentExercise,
              lastCompletedSetLabel: lastIdx < 0
                  ? null
                  : _setLabel(lastSets, lastIdx).toLowerCase(),
              onMinimize: () {
                ref.read(dynamicRestTimerMinimizedProvider.notifier).state =
                    true;
                if (_restDone) {
                  setState(() => _restDone = false);
                  _syncInterstitial();
                }
              },
              onStartNext: () {
                setState(() => _restDone = false);
                _syncInterstitial();
              },
              onFinishWorkout: _finishWorkout,
              onOpenRpe: (set) async {
                await _promptFullScreenRpe(
                  targetSet: set,
                  catalogExercise:
                      _lastCompletedExerciseCatalog ?? currentExercise,
                  sets: lastSets,
                  setIndex: lastIdx >= 0 ? lastIdx : effectiveSetIdx,
                );
              },
            ),
          ),

        if (_done case final done?)
          Positioned.fill(
            child: _DoneScreen(
              done: done,
              session: widget.session,
              exercises: exercises,
              catalog: catalog,
              onBack: () {
                setState(() => _done = null);
                _syncInterstitial();
              },
              onContinue: () {
                final next = done.nextIndex;
                if (next != null) _goToExercise(next, exercises);
                if (ref.read(restTimerProvider).isRunning) {
                  ref.read(dynamicRestTimerMinimizedProvider.notifier).state =
                      true;
                }
                setState(() {
                  _done = null;
                  _restDone = false;
                });
                _syncInterstitial();
              },
              onFinish: _finishWorkout,
            ),
          ),
      ],
    );
  }

  /// Prompts the full-screen RPE selector view for a completed set.
  Future<void> _promptFullScreenRpe({
    required SetEntryData targetSet,
    required ExerciseCatalogData? catalogExercise,
    required List<SetEntryData> sets,
    required int setIndex,
  }) => _promptRpe(
    context,
    ref,
    targetSet: targetSet,
    exerciseName: catalogExercise?.name ?? 'Exercise',
    setLabel: _setLabel(sets, setIndex, withTotal: true),
  );

  /// "Complete set", or — once every set of this exercise is done —
  /// "Continue" to the next exercise / "Finish workout".
  Widget _buildPrimaryAction({
    required List<WorkoutExerciseData> exercises,
    required WorkoutExerciseData currentWe,
    required ExerciseCatalogData? currentExercise,
    required List<SetEntryData> currentSets,
    required SetEntryData? activeSet,
    required int effectiveSetIdx,
  }) {
    final targetSet =
        activeSet ?? currentSets.firstWhereOrNull((s) => !s.isCompleted);
    final allCurrentSetsCompleted =
        currentSets.isNotEmpty && currentSets.every((s) => s.isCompleted);
    final hasNextExercise = _exerciseIndex < exercises.length - 1;

    if (targetSet == null || allCurrentSetsCompleted) {
      return hasNextExercise
          ? WorkoutHeroButton(
              label: 'Continue',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: () => _goToExercise(_exerciseIndex + 1, exercises),
            )
          : WorkoutHeroButton(
              label: 'Finish workout',
              trailingIcon: Icons.emoji_events_rounded,
              color: context.hx.success,
              foreground: successInk,
              onPressed: _finishWorkout,
            );
    }

    return WorkoutHeroButton(
      label: targetSet.isCompleted ? 'Re-log set' : 'Complete set',
      leadingIcon: Icons.check_circle_rounded,
      onPressed: () => _completeSet(
        exercises: exercises,
        currentWe: currentWe,
        currentExercise: currentExercise,
        currentSets: currentSets,
        targetSet: targetSet,
        effectiveSetIdx: effectiveSetIdx,
      ),
    );
  }

  Future<void> _completeSet({
    required List<WorkoutExerciseData> exercises,
    required WorkoutExerciseData currentWe,
    required ExerciseCatalogData? currentExercise,
    required List<SetEntryData> currentSets,
    required SetEntryData targetSet,
    required int effectiveSetIdx,
  }) async {
    Haptics.medium();
    final repo = ref.read(workoutsRepositoryProvider);
    final ex = currentExercise;

    ref.read(dynamicRestTimerMinimizedProvider.notifier).state = false;
    setState(() {
      _lastCompletedSet = targetSet;
      _lastCompletedSetId = targetSet.id;
      _lastCompletedExerciseCatalog = ex;
      _restDone = false;
    });
    _syncInterstitial();

    final target = await ref.read(workoutTargetsProvider(currentWe.id).future);
    final suggested = target[targetSet.id];
    await repo.updateSet(
      setId: targetSet.id,
      isCompleted: true,
      weightKg: targetSet.hasEnteredWeight ? null : suggested?.weightKg,
      reps: targetSet.reps > 0 ? null : suggested?.reps,
    );

    if (ex != null && !targetSet.isWarmup) {
      final effectiveKg =
          (isMachineAssistedPullup(ex.slug)
              ? -targetSet.weightKg
              : targetSet.weightKg) +
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

    // Where the next set is. The rest timer starts itself from the database
    // change (restTimerAutoStartProvider).
    final open = <int, bool>{};
    for (final we in exercises) {
      final sets = await repo.watchSetsForWorkoutExercise(we.id).first;
      open[we.id] = sets.any((s) => !s.isCompleted);
    }
    if (!mounted) return;
    final (nextIdx, done) = _nextStep(exercises, currentWe, open);

    if (nextIdx != null && nextIdx != _exerciseIndex) {
      _goToExercise(nextIdx, exercises);
    }

    await _promptFullScreenRpe(
      targetSet: targetSet,
      catalogExercise: ex,
      sets: currentSets,
      setIndex: effectiveSetIdx,
    );
    if (!mounted || done == null) return;
    if (done.stage == _DoneStage.workout) {
      ref.read(restTimerProvider.notifier).cancel();
    }
    setState(() => _done = done);
    _syncInterstitial();
  }
}
