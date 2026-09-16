import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/keyboard_obstruction_scope.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';
import 'package:herculex/features/buddy/presentation/buddy_presence_bar.dart';
import 'package:herculex/features/buddy/presentation/buddy_share_sheet.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/workouts/application/circuits_providers.dart';
import 'package:herculex/features/workouts/application/finish_workout_action.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/circuit_stats.dart';
import 'package:herculex/features/workouts/domain/workout_name_generator.dart';
import 'package:herculex/features/workouts/presentation/dialogs/duration_picker_dialog.dart';
import 'package:herculex/features/workouts/presentation/sheets/equipment_variant_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/exercise_picker_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/workout_settings_sheet.dart';
import 'package:herculex/features/workouts/presentation/views/dynamic_workout_view.dart';
import 'package:herculex/features/workouts/presentation/views/workout_finish_view.dart';
import 'package:herculex/features/workouts/presentation/widgets/active_exercise_card.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';
import 'package:herculex/features/workouts/presentation/widgets/rest_timer_banner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ActiveWorkoutView extends ConsumerStatefulWidget {
  final WorkoutSessionData session;
  const ActiveWorkoutView({super.key, required this.session});

  @override
  ConsumerState<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends ConsumerState<ActiveWorkoutView>
    with WidgetsBindingObserver {
  final Map<int, FocusNode> _firstSetFocusNodes = {};
  // While a drag is in progress the list collapses every exercise (and each
  // superset's exercises together) into compact pills, so long lists stay
  // legible enough to actually see where a row is landing.
  bool _reorderMode = false;

  /// Buckets [rows] into superset groups, preserving first-appearance order
  /// so a linked group always drags — and lands — as one unit.
  List<List<WorkoutExerciseData>> _groupRows(List<WorkoutExerciseData> rows) {
    final groups = <List<WorkoutExerciseData>>[];
    final indexByGroupId = <int, int>{};
    for (final row in rows) {
      final groupId = row.supersetGroup;
      if (groupId == null) {
        groups.add([row]);
        continue;
      }
      final existingIndex = indexByGroupId[groupId];
      if (existingIndex == null) {
        indexByGroupId[groupId] = groups.length;
        groups.add([row]);
      } else {
        groups[existingIndex].add(row);
      }
    }
    return groups;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Enable wakelock if the user preference is on (default: true).
    _applyWakelock();
  }

  void _applyWakelock() {
    final keepAwake = ref.read(keepAwakeProvider);
    WakelockPlus.toggle(enable: keepAwake);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Always release the wakelock when leaving the workout screen.
    WakelockPlus.disable();
    for (final node in _firstSetFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Scaffold removes the bottom MediaQuery inset from its body while it
    // resizes. Listening to platform metrics keeps this floating bar in sync
    // with the actual keyboard instead.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final editingOriginalEndedAt = ref.watch(
      editingSessionOriginalEndedAtProvider,
    )[session.id];
    final sessionExercises = ref.watch(sessionExercisesProvider(session.id));
    final liveStats =
        ref.watch(activeSessionStatsProvider(session.id)).valueOrNull ??
        const LiveWorkoutStats();
    final weightFormat = ref.watch(weightFormatProvider);
    final catalog = ref.watch(
      exerciseCatalogProvider(const ExerciseCatalogFilter()),
    );
    final repo = ref.watch(workoutsRepositoryProvider);
    final buddyState = ref.watch(buddySessionControllerProvider);
    final buddySender = buddyState.isSharing
        ? ref.watch(
            buddyChoreographySenderProvider((
              buddySessionId: buddyState.buddySessionId!,
              localWorkoutSessionId: session.id,
            )),
          )
        : null;

    // One-tap switch between Classic and Dynamic full-screen mode (§14).
    if (ref.watch(dynamicWorkoutModeProvider)) {
      return DynamicWorkoutView(session: session);
    }
    final inputFocused = ref.watch(workoutInputFocusedProvider);
    final keyboardOpen = _keyboardOpen(context) || inputFocused;
    // Floating action bar sits above the nav bar and overlays the list.
    return Stack(
      children: [
        // ── Main scrollable column ──────────────────────────────────────
        Column(
          children: [
            // Top SafeArea so the header clears the status bar / notch.
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                _editWorkoutName(context, ref, session),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    (session.name != null &&
                                            session.name!.isNotEmpty)
                                        ? session.name!
                                        : 'Workout in progress',
                                    style: theme.textTheme.displayMedium
                                        ?.copyWith(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.group_add_outlined, size: 22),
                          tooltip: 'Gym Buddy',
                          onPressed: () => BuddyShareSheet.show(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, size: 22),
                          tooltip: 'Workout settings',
                          onPressed: () => WorkoutSettingsSheet.show(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.fullscreen, size: 22),
                          tooltip: 'Dynamic mode',
                          onPressed: () =>
                              ref
                                      .read(dynamicWorkoutModeProvider.notifier)
                                      .state =
                                  true,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 22),
                          tooltip: 'Cancel workout',
                          onPressed: () => _confirmCancel(context, ref),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ActiveWorkoutStatsBar(
                      startedAt: session.startedAt,
                      originalEndedAt: editingOriginalEndedAt,
                      formatElapsed: _elapsed,
                      totalSets: liveStats.totalSets,
                      completedSets: liveStats.completedSets,
                      tonnageText: weightFormat.formatTonnage(
                        liveStats.totalTonnageKg,
                      ),
                      onEditDuration: () async {
                        final currentDur = _resolvedEndedAt(
                          session.startedAt,
                          editingOriginalEndedAt,
                        ).difference(session.startedAt);
                        final newMins = await DurationPickerDialog.show(
                          context,
                          initialMinutes: currentDur.inMinutes > 0
                              ? currentDur.inMinutes
                              : 45,
                        );
                        if (newMins != null && newMins > 0) {
                          final newEndedAt = session.startedAt.add(
                            Duration(minutes: newMins),
                          );
                          ref
                              .read(
                                editingSessionOriginalEndedAtProvider.notifier,
                              )
                              .update(
                                (state) => {...state, session.id: newEndedAt},
                              );
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const BuddyPresenceBar(),
            const _HealthActivityAdjustmentBanner(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: RestTimerBanner(),
            ),
            Expanded(
              child: sessionExercises.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fitness_center,
                            size: 56,
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No exercises yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + Add Exercise to start logging',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }
                  final groups = _groupRows(rows);
                  return ReorderableListView.builder(
                    // Enough clearance for the floating bar + nav bar.
                    padding: const EdgeInsets.only(bottom: 200),
                    itemCount: groups.length,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, _, animation) => AnimatedBuilder(
                      animation: animation,
                      builder: (_, child) => Transform.scale(
                        scale: 1 + animation.value * 0.02,
                        child: Material(
                          elevation: 8 * animation.value,
                          color: Colors.transparent,
                          child: child,
                        ),
                      ),
                      child: child,
                    ),
                    onReorderStart: (_) => setState(() => _reorderMode = true),
                    onReorderEnd: (_) => setState(() => _reorderMode = false),
                    onReorderItem: (oldIndex, newIndex) {
                      var targetIndex = newIndex;
                      if (targetIndex > oldIndex) targetIndex -= 1;
                      final reorderedGroups = List<List<WorkoutExerciseData>>.from(
                        groups,
                      );
                      final movedGroup = reorderedGroups.removeAt(oldIndex);
                      reorderedGroups.insert(targetIndex, movedGroup);
                      final orderedIds = reorderedGroups
                          .expand((group) => group)
                          .map((r) => r.id)
                          .toList();
                      repo.reorderWorkoutExerciseGroups(
                        sessionId: session.id,
                        orderedWorkoutExerciseIds: orderedIds,
                      );
                      buddySender?.reorder(
                        workoutExerciseIdsInOrder: orderedIds,
                        scope: BuddyScope.both,
                      );
                    },
                    itemBuilder: (_, i) {
                      final group = groups[i];
                      return _ExerciseGroupTile(
                        key: ValueKey('exercise_group_${group.first.id}'),
                        groupIndex: i,
                        members: group,
                        reorderMode: _reorderMode,
                        catalogExercises: catalog.asData?.value ?? const [],
                        placeholderExercise: _placeholderExercise,
                        cardBuilder: (we, exercise, dragHandle) =>
                            ActiveExerciseCard(
                              workoutExercise: we,
                              exercise: exercise,
                              sessionExercises: rows,
                              catalogExercises:
                                  catalog.asData?.value ?? const [],
                              firstSetFocusNode: _focusNodeFor(we.id),
                              onCompletedSet:
                                  (completedWorkoutExerciseId, setIndex) =>
                                      _advanceWithinLinkedGroup(
                                        rows,
                                        completedWorkoutExerciseId,
                                        setIndex,
                                      ),
                              onRemove: () {
                                if (buddySender != null) {
                                  buddySender.removeExercise(
                                    workoutExerciseId: we.id,
                                    scope: BuddyScope.mine,
                                  );
                                } else {
                                  repo.removeWorkoutExercise(we.id);
                                }
                              },
                              dragHandle: dragHandle,
                            ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
        // ── Floating action bar ─────────────────────────────────────────
        // Hidden while the keyboard is up (logging kg/reps/RPE) so it never
        // covers the field being edited; slides back in once it closes.
        KeyboardObstructionScope(
          hidden: keyboardOpen,
          hiddenOffset: 140,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              child: Row(
                children: [
                  Expanded(
                    child: _FloatyButton(
                      text: 'Exercise',
                      icon: Icons.add,
                      isPrimary: false,
                      onTap: () async {
                        final results = await ExercisePickerSheet.show(
                          context,
                        );
                        if (results == null ||
                            results.isEmpty ||
                            !context.mounted) {
                          return;
                        }
                        final circuitIds = <int>{};
                        for (final result in results) {
                          if (!context.mounted) return;
                          if (result.circuitId != null) {
                            if (!circuitIds.contains(result.circuitId!)) {
                              circuitIds.add(result.circuitId!);
                              await ref
                                  .read(circuitsRepositoryProvider)
                                  .addCircuitToSession(
                                    sessionId: session.id,
                                    circuitId: result.circuitId!,
                                  );
                            }
                            continue;
                          }
                          final picked = result.exercise;
                          final String? variant =
                              result.equipmentVariant ??
                              ((results.length > 1 ||
                                      result.equipmentAlreadyChosen)
                                  ? picked.modality
                                  : await EquipmentVariantSheet.show(
                                      context,
                                      picked,
                                    ));
                          if (variant == null) continue;
                          if (buddySender != null) {
                            await buddySender.addExercise(
                              exerciseId: picked.id,
                              equipmentVariant: variant,
                              scope: BuddyScope.both,
                            );
                          } else {
                            await repo.addExerciseToSession(
                              sessionId: session.id,
                              exerciseId: picked.id,
                              equipmentVariant: variant,
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _FloatyButton(
                      text: 'Finish',
                      icon: Icons.check,
                      isPrimary: true,
                      onTap: () async {
                        await _showFinishSummary(session);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _keyboardOpen(BuildContext context) =>
      View.of(context).viewInsets.bottom > 0;

  DateTime _resolvedEndedAt(DateTime startedAt, DateTime? originalEndedAt) {
    if (originalEndedAt != null) return originalEndedAt;
    final now = DateTime.now();
    if (now.difference(startedAt).inHours >= 12) {
      return startedAt.add(const Duration(minutes: 45));
    }
    return now;
  }

  String _elapsed(DateTime startedAt, {DateTime? originalEndedAt}) {
    final ended = _resolvedEndedAt(startedAt, originalEndedAt);
    final d = ended.difference(startedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  FocusNode _focusNodeFor(int workoutExerciseId) {
    return _firstSetFocusNodes.putIfAbsent(workoutExerciseId, FocusNode.new);
  }

  bool _advanceWithinLinkedGroup(
    List<WorkoutExerciseData> rows,
    int workoutExerciseId,
    int setIndex,
  ) {
    final currentIndex = rows.indexWhere((r) => r.id == workoutExerciseId);
    if (currentIndex < 0) return false;
    final currentEx = rows[currentIndex];
    final group = currentEx.supersetGroup;
    if (group == null) return false;

    final groupRows = rows.where((r) => r.supersetGroup == group).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (groupRows.length <= 1) return false;
    final groupIndex = groupRows.indexWhere((r) => r.id == workoutExerciseId);
    if (groupIndex < 0) return false;

    final isLastInGroup = groupIndex == groupRows.length - 1;
    if (isLastInGroup) {
      // Completed the round for the entire superset / giant set group!
      final rest = currentEx.targetRestSeconds ?? 90;
      final groupLabel = groupRows.length == 2
          ? 'Superset'
          : (groupRows.length == 3 ? 'Tri-Set' : 'Giant Set');
      ref
          .read(restTimerProvider.notifier)
          .start(
            seconds: rest,
            exerciseName: '$groupLabel Rest (Round $setIndex)',
          );
      // Dismiss keyboard cleanly when round ends — user is resting
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      // Intra-round transition between linked exercises: dismiss keyboard cleanly
      FocusManager.instance.primaryFocus?.unfocus();
    }
    return true;
  }

  ExerciseCatalogData _placeholderExercise(int id) => ExerciseCatalogData(
    id: id,
    name: 'Loading…',
    primaryMuscle: '',
    equipment: '',
    mechanics: '',
    force: '',
    plane: '',
    defaultRestSeconds: 120,
    maxEffortEligibility: 'unsuitable',
    isCustom: false,
    category: 'strength',
    modality: 'barbell',
    cnsScore: 3,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: false,
    isReviewed: false,
  );

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    final editingOriginalEndedAt = ref.read(
      editingSessionOriginalEndedAtProvider,
    )[widget.session.id];
    final isEditingPastWorkout = editingOriginalEndedAt != null;

    // Same disposal hazard as the finish flow: `endSession`/`deleteSession`
    // both drop this session out of `activeSessionProvider`, disposing this
    // widget mid-handler. Everything the handlers need is read up front.
    final db = ref.read(appDatabaseProvider);
    final repo = ref.read(workoutsRepositoryProvider);
    final wearSync = ref.read(wearWorkoutSyncServiceProvider);
    final editedEndedAt = ref.read(
      editingSessionOriginalEndedAtProvider.notifier,
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEditingPastWorkout
              ? 'Close workout edit?'
              : 'Close active workout?',
        ),
        content: Text(
          isEditingPastWorkout
              ? 'Choose how to exit editing:'
              : 'Choose what to do with this workout:',
        ),
        actions: [
          // 1. Cancel: Close dialog and continue editing
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          // 2. Keep: Keep workout saved and exit view
          FilledButton.tonal(
            onPressed: () async {
              // Pop before the write, not after: the write disposes this
              // screen, taking `ctx` with it.
              Navigator.pop(ctx);
              if (isEditingPastWorkout) {
                final stmt = db.update(db.workoutSessions)
                  ..where((t) => t.id.equals(widget.session.id));
                await stmt.write(
                  WorkoutSessionsCompanion(
                    endedAt: drift.Value(editingOriginalEndedAt),
                  ),
                );
              } else {
                await repo.endSession(widget.session.id);
                wearSync.notifySessionEnded(widget.session.sessionUuid);
              }
            },
            child: const Text('Keep Workout'),
          ),
          // 3. Discard: Discard edits or delete new session
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (isEditingPastWorkout) {
                final stmt = db.update(db.workoutSessions)
                  ..where((t) => t.id.equals(widget.session.id));
                await stmt.write(
                  WorkoutSessionsCompanion(
                    endedAt: drift.Value(editingOriginalEndedAt),
                  ),
                );
                editedEndedAt.update((state) {
                  final copy = Map<int, DateTime>.from(state);
                  copy.remove(widget.session.id);
                  return copy;
                });
              } else {
                await repo.deleteSession(widget.session.id);
                wearSync.notifySessionEnded(widget.session.sessionUuid);
              }
            },
            child: Text(
              isEditingPastWorkout ? 'Discard Edits' : 'Discard Workout',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  // Takes neither `context` nor `ref`: both are already fields on this State,
  // and shadowing `State.context` with a parameter defeats the analyzer's
  // async-gap checking — which is precisely the class of bug this routine had.
  Future<void> _showFinishSummary(WorkoutSessionData session) async {
    final editingOriginalEndedAt = ref.read(
      editingSessionOriginalEndedAtProvider,
    )[session.id];
    final repo = ref.read(workoutsRepositoryProvider);

    String defaultWorkoutName = session.name?.trim() ?? '';
    if (defaultWorkoutName.isEmpty || defaultWorkoutName == 'Awesome Workout') {
      final sessionExercises =
          ref.read(sessionExercisesProvider(session.id)).asData?.value ?? [];
      final catalogSnapshot = ref
          .read(exerciseCatalogSnapshotProvider)
          .asData
          ?.value;
      if (sessionExercises.isNotEmpty && catalogSnapshot != null) {
        final exercises = sessionExercises
            .map((we) => catalogSnapshot.find(we.exerciseId))
            .whereType<ExerciseCatalogData>()
            .toList();
        defaultWorkoutName = WorkoutNameGenerator.generate(exercises);
      } else {
        final exercises = await repo.getExercisesForSession(session.id);
        defaultWorkoutName = WorkoutNameGenerator.generate(exercises);
      }
    }

    // After the `getExercisesForSession` await above — creating the controller
    // before the bail-out leaked one on every early return.
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: defaultWorkoutName);

    // Resolved before the dialog opens, and re-resolved nowhere: `endSession`
    // disposes this widget (see FinishWorkoutAction's doc comment), so a
    // `ref.read` after that await throws.
    final finish = FinishWorkoutAction.resolve(ref);
    // The app-level navigator outlives this screen; `context` does not.
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    // Dialog-local, deliberately not a `ref.watch` on the StateProvider: this
    // builder outlives the widget whose `ref` it would capture, and a
    // `ref.watch` from a disposed element throws *during build* — the red
    // screen this whole routine used to produce.
    DateTime? currentEndedAt = editingOriginalEndedAt;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Finish Workout'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Name this workout:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Duration: ${_elapsed(session.startedAt, originalEndedAt: currentEndedAt)}',
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          final currentDur = _resolvedEndedAt(
                            session.startedAt,
                            currentEndedAt,
                          ).difference(session.startedAt);
                          final newMins = await DurationPickerDialog.show(
                            context,
                            initialMinutes: currentDur.inMinutes > 0
                                ? currentDur.inMinutes
                                : 45,
                          );
                          if (newMins != null && newMins > 0) {
                            setStateDialog(() {
                              currentEndedAt = session.startedAt.add(
                                Duration(minutes: newMins),
                              );
                            });
                          }
                        },
                        child: Text(
                          'Change',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Resume'),
                ),
                TextButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final finalName = name.isEmpty ? defaultWorkoutName : name;
                    final finalEndedAt = currentEndedAt;

                    await ref
                        .read(templatesRepositoryProvider)
                        .saveSessionAsTemplate(session.id, finalName);

                    await finish.run(
                      session: session,
                      name: finalName,
                      endedAt: finalEndedAt,
                    );

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);

                    if (!rootNavigator.mounted) return;
                    await WorkoutFinishView.show(
                      rootNavigator.context,
                      session.id,
                    );
                  },
                  child: const Text('Save as template'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final finalName = name.isEmpty ? defaultWorkoutName : name;
                    final finalEndedAt = currentEndedAt;

                    await finish.run(
                      session: session,
                      name: finalName,
                      endedAt: finalEndedAt,
                    );

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);

                    if (!rootNavigator.mounted) return;
                    await WorkoutFinishView.show(
                      rootNavigator.context,
                      session.id,
                    );
                  },
                  child: const Text('Finish'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  void _editWorkoutName(
    BuildContext context,
    WidgetRef ref,
    WorkoutSessionData session,
  ) {
    final controller = TextEditingController(text: session.name ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Workout Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Workout name (e.g. Chest & Triceps)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await ref
                    .read(workoutsRepositoryProvider)
                    .updateSessionName(session.id, newName);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Renders one drag target in the reorderable list — a single exercise, or
/// (when [members] has more than one row) a whole superset group that always
/// drags and lands together, since [groupIndex] is the one index every
/// member's drag handle reports to `ReorderableListView`.
class _ExerciseGroupTile extends ConsumerWidget {
  final int groupIndex;
  final List<WorkoutExerciseData> members;
  final bool reorderMode;
  final List<ExerciseCatalogData> catalogExercises;
  final ExerciseCatalogData Function(int exerciseId) placeholderExercise;
  final Widget Function(
    WorkoutExerciseData workoutExercise,
    ExerciseCatalogData exercise,
    Widget dragHandle,
  )
  cardBuilder;

  const _ExerciseGroupTile({
    super.key,
    required this.groupIndex,
    required this.members,
    required this.reorderMode,
    required this.catalogExercises,
    required this.placeholderExercise,
    required this.cardBuilder,
  });

  ExerciseCatalogData _exerciseFor(WorkoutExerciseData we) {
    return catalogExercises.firstWhere(
      (e) => e.id == we.exerciseId,
      orElse: () => placeholderExercise(we.exerciseId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLinked = members.length > 1;
    final groupCount = members.length;
    final label = groupCount == 2
        ? 'SUPERSET'
        : (groupCount == 3 ? 'TRI-SET' : 'GIANT SET');
    final tooltipMsg = groupCount == 2
        ? 'Superset'
        : (groupCount == 3 ? 'Tri-Set' : 'Giant Set');

    final dragHandle = Tooltip(
      message: 'Hold to reorder',
      child: ReorderableDelayedDragStartListener(
        index: groupIndex,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Icon(
            Icons.drag_indicator,
            size: 20,
            color: AppColors.secondary,
          ),
        ),
      ),
    );

    if (reorderMode) {
      return _ReorderPillGroup(
        members: members,
        isLinked: isLinked,
        label: label,
        exerciseFor: _exerciseFor,
        dragHandle: dragHandle,
      );
    }

    // Calculate circuit metrics
    CircuitPerformanceStats stats = CircuitPerformanceStats.empty;
    if (isLinked) {
      final setsByExercise = <int, List<SetEntryData>>{};
      for (final gr in members) {
        final setsAsync = ref.watch(workoutExerciseSetsProvider(gr.id));
        setsByExercise[gr.id] = setsAsync.asData?.value ?? [];
      }
      stats = calculateCircuitStats(
        exercises: members,
        setsByExerciseId: setsByExercise,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var j = 0; j < members.length; j++)
          _buildMember(
            member: members[j],
            memberIndex: j,
            isLinked: isLinked,
            isFirst: j == 0,
            isLast: j == members.length - 1,
            label: label,
            tooltipMsg: tooltipMsg,
            stats: stats,
            dragHandle: dragHandle,
          ),
      ],
    );
  }

  Widget _buildMember({
    required WorkoutExerciseData member,
    required int memberIndex,
    required bool isLinked,
    required bool isFirst,
    required bool isLast,
    required String label,
    required String tooltipMsg,
    required CircuitPerformanceStats stats,
    required Widget dragHandle,
  }) {
    final exercise = _exerciseFor(member);
    return Stack(
      children: [
        if (isLinked)
          Positioned(
            left: 20,
            top: isFirst ? 42 : 0,
            bottom: isLast ? 34 : 0,
            child: Container(width: 3, color: AppColors.primary),
          ),
        if (isLinked)
          Positioned(
            left: 12,
            top: isFirst ? 48 : 27,
            child: Tooltip(
              message: tooltipMsg,
              child: Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: Text(
                  '${memberIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(left: isLinked ? 18 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLinked && isFirst)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Rounds: ${stats.completedRounds}/${stats.totalPlannedRounds}',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 1,
                        height: 12,
                        color: AppColors.outlineVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Avg Rest: ${stats.formattedAvgRest}',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              cardBuilder(member, exercise, dragHandle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact reorder-mode stand-in for a group's full exercise cards — just
/// enough (artwork, name, drag handle) to see where a row is landing when
/// the list is long. Linked exercises stay visually bracketed together so
/// it stays obvious they'll move as one.
class _ReorderPillGroup extends StatelessWidget {
  final List<WorkoutExerciseData> members;
  final bool isLinked;
  final String label;
  final ExerciseCatalogData Function(WorkoutExerciseData) exerciseFor;
  final Widget dragHandle;

  const _ReorderPillGroup({
    required this.members,
    required this.isLinked,
    required this.label,
    required this.exerciseFor,
    required this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final pills = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var j = 0; j < members.length; j++)
          Padding(
            padding: EdgeInsets.only(top: j == 0 ? 0 : 6),
            child: _ReorderPill(
              exercise: exerciseFor(members[j]),
              dragHandle: dragHandle,
            ),
          ),
      ],
    );

    if (!isLinked) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: pills,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Row(
              children: [
                Icon(Icons.repeat_rounded, size: 13, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          pills,
        ],
      ),
    );
  }
}

class _ReorderPill extends StatelessWidget {
  final ExerciseCatalogData exercise;
  final Widget dragHandle;

  const _ReorderPill({required this.exercise, required this.dragHandle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          ExerciseArtwork(exercise: exercise, size: 28, radius: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              exercise.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          dragHandle,
        ],
      ),
    );
  }
}

class _FloatyButton extends StatefulWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _FloatyButton({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  State<_FloatyButton> createState() => _FloatyButtonState();
}

class _FloatyButtonState extends State<_FloatyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bgColor = widget.isPrimary
        ? AppColors.primary
        : AppColors.surfaceContainer;
    final textColor = widget.isPrimary
        ? Colors.white
        : theme.colorScheme.onSurface;
    final borderColor = widget.isPrimary
        ? Colors.transparent
        : AppColors.outlineVariant;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: textColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthActivityAdjustmentBanner extends ConsumerWidget {
  const _HealthActivityAdjustmentBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjAsync = ref.watch(activityBasedAdjustmentProvider);
    final adj = adjAsync.asData?.value;
    if (adj == null || adj.volumeFactor >= 1.0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isRest = adj.volumeFactor == 0.0;
    final accentColor = isRest ? Colors.redAccent : const Color(0xFFFFB300);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRest ? Icons.nightlife_rounded : Icons.directions_walk_rounded,
            color: accentColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adj.statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  adj.message,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutTimerText extends StatelessWidget {
  final DateTime startedAt;
  final DateTime? originalEndedAt;
  final String Function(DateTime startedAt, {DateTime? originalEndedAt})
  formatElapsed;

  const _WorkoutTimerText({
    required this.startedAt,
    required this.originalEndedAt,
    required this.formatElapsed,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                formatElapsed(startedAt, originalEndedAt: originalEndedAt),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.edit_outlined,
              size: 10,
              color: AppColors.primary.withValues(alpha: 0.8),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveWorkoutStatsBar extends StatelessWidget {
  final DateTime startedAt;
  final DateTime? originalEndedAt;
  final String Function(DateTime startedAt, {DateTime? originalEndedAt})
  formatElapsed;
  final int totalSets;
  final int completedSets;
  final String tonnageText;
  final VoidCallback onEditDuration;

  const _ActiveWorkoutStatsBar({
    required this.startedAt,
    required this.originalEndedAt,
    required this.formatElapsed,
    required this.totalSets,
    required this.completedSets,
    required this.tonnageText,
    required this.onEditDuration,
  });

  @override
  Widget build(BuildContext context) {
    final setsText = totalSets == 0
        ? '0'
        : (completedSets == totalSets
              ? '$totalSets'
              : '$completedSets / $totalSets');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.surfaceVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 1. Time / Duration
          Expanded(
            child: InkWell(
              onTap: onEditDuration,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: AppColors.primary.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'TIME',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    _WorkoutTimerText(
                      startedAt: startedAt,
                      originalEndedAt: originalEndedAt,
                      formatElapsed: formatElapsed,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            height: 28,
            width: 1,
            color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          ),
          // 2. Sets
          Expanded(
            child: _StatColumn(
              icon: Icons.format_list_numbered_rounded,
              iconColor: const Color(0xFFFF9800),
              label: 'SETS',
              value: setsText,
            ),
          ),
          Container(
            height: 28,
            width: 1,
            color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          ),
          // 3. Volume / Tonnage
          Expanded(
            child: _StatColumn(
              icon: Icons.fitness_center_rounded,
              iconColor: const Color(0xFF26C6DA),
              label: 'VOLUME',
              value: tonnageText,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iconColor.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
