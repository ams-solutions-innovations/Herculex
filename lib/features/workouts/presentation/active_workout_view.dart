import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../health/presentation/health_providers.dart';
import 'active_exercise_card.dart';
import 'duration_picker_dialog.dart';
import 'dynamic_workout_view.dart';
import 'equipment_variant_sheet.dart';
import 'exercise_picker_sheet.dart';
import 'media_controls_sheet.dart';
import 'rest_timer_banner.dart';
import 'workout_finish_view.dart';
import 'workout_settings_sheet.dart';
import 'workouts_providers.dart';

class ActiveWorkoutView extends ConsumerStatefulWidget {
  final WorkoutSessionData session;
  const ActiveWorkoutView({super.key, required this.session});

  @override
  ConsumerState<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends ConsumerState<ActiveWorkoutView> {
  Timer? _ticker;
  final Map<int, FocusNode> _firstSetFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Enable wakelock if the user preference is on (default: true).
    _applyWakelock();

  }

  void _applyWakelock() {
    final keepAwake = ref.read(keepAwakeProvider);
    WakelockPlus.toggle(enable: keepAwake);
  }



  @override
  void dispose() {
    _ticker?.cancel();

    // Always release the wakelock when leaving the workout screen.
    WakelockPlus.disable();
    for (final node in _firstSetFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final editingOriginalEndedAt =
        ref.watch(editingSessionOriginalEndedAtProvider)[session.id];
    final sessionExercises = ref.watch(sessionExercisesProvider(session.id));
    final catalog = ref.watch(
      exerciseCatalogProvider(const ExerciseCatalogFilter()),
    );
    final repo = ref.watch(workoutsRepositoryProvider);

    // One-tap switch between Classic and Dynamic full-screen mode (§14).
    if (ref.watch(dynamicWorkoutModeProvider)) {
      return DynamicWorkoutView(session: session);
    }
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
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _editWorkoutName(context, ref, session),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              (session.name != null && session.name!.isNotEmpty)
                                  ? session.name!
                                  : 'Workout in progress',
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontSize: 24,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        InkWell(
                          onTap: () async {
                            final currentDur =
                                _resolvedEndedAt(session.startedAt, editingOriginalEndedAt)
                                    .difference(session.startedAt);
                            final newMins = await DurationPickerDialog.show(
                              context,
                              initialMinutes:
                                  currentDur.inMinutes > 0 ? currentDur.inMinutes : 45,
                            );
                            if (newMins != null && newMins > 0) {
                              final newEndedAt =
                                  session.startedAt.add(Duration(minutes: newMins));
                              ref
                                  .read(editingSessionOriginalEndedAtProvider.notifier)
                                  .update((state) => {...state, session.id: newEndedAt});
                              setState(() {});
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _elapsed(session.startedAt,
                                      originalEndedAt: editingOriginalEndedAt),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.edit_outlined,
                                    size: 14, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Workout settings',
                          onPressed: () => WorkoutSettingsSheet.show(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.fullscreen),
                          tooltip: 'Dynamic mode',
                          onPressed: () =>
                              ref.read(dynamicWorkoutModeProvider.notifier).state = true,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel workout',
                          onPressed: () => _confirmCancel(context, ref),
                        ),
                      ],
                    ),
                  ],
                ),
            ),
          ),
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
                  return ReorderableListView.builder(
                    // Enough clearance for the floating bar + nav bar.
                    padding: const EdgeInsets.only(bottom: 200),
                    itemCount: rows.length,
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
                    onReorder: (oldIndex, newIndex) => repo.reorderWorkoutExercises(
                      sessionId: session.id,
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                    ),
                    itemBuilder: (_, i) {
                      final we = rows[i];
                      final exercise = catalog.asData?.value.firstWhere(
                        (e) => e.id == we.exerciseId,
                        orElse: () => _placeholderExercise(we.exerciseId),
                      );
                      if (exercise == null) {
                        return SizedBox.shrink(key: ValueKey('exercise_${we.id}'));
                      }
                      return _LinkedExerciseTile(
                        key: ValueKey('exercise_${we.id}'),
                        index: i,
                        workoutExercise: we,
                        rows: rows,
                        builder: (_, dragHandle) => ActiveExerciseCard(
                          workoutExercise: we,
                          exercise: exercise,
                          sessionExercises: rows,
                          catalogExercises: catalog.asData?.value ?? const [],
                          firstSetFocusNode: _focusNodeFor(we.id),
                          onCompletedSet: (completedWorkoutExerciseId, setIndex) =>
                              _advanceWithinLinkedGroup(
                                rows,
                                completedWorkoutExerciseId,
                                setIndex,
                              ),
                          onRemove: () => repo.removeWorkoutExercise(we.id),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
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
                        final results = await ExercisePickerSheet.show(context);
                        if (results == null || results.isEmpty || !context.mounted) return;
                        for (final result in results) {
                          if (!context.mounted) return;
                          final picked = result.exercise;
                          final String? variant =
                              (results.length > 1 || result.equipmentAlreadyChosen)
                                  ? picked.modality
                                  : await EquipmentVariantSheet.show(
                                      context,
                                      picked,
                                    );
                          if (variant == null) continue;
                          await repo.addExerciseToSession(
                            sessionId: session.id,
                            exerciseId: picked.id,
                            equipmentVariant: variant,
                          );
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
                        await _showFinishSummary(context, ref, session);
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
    final group = rows[currentIndex].supersetGroup;
    if (group == null) return false;

    final groupRows = rows.where((r) => r.supersetGroup == group).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final groupIndex = groupRows.indexWhere((r) => r.id == workoutExerciseId);
    if (groupIndex < 0 || groupIndex == groupRows.length - 1) return false;

    final next = groupRows[groupIndex + 1];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstSetFocusNodes[next.id]?.requestFocus();
    });
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
    final editingOriginalEndedAt =
        ref.read(editingSessionOriginalEndedAtProvider)[widget.session.id];
    final isEditingPastWorkout = editingOriginalEndedAt != null;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditingPastWorkout ? 'Close workout edit?' : 'Close active workout?'),
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
              if (isEditingPastWorkout) {
                final db = ref.read(appDatabaseProvider);
                final stmt = db.update(db.workoutSessions)
                  ..where((t) => t.id.equals(widget.session.id));
                await stmt.write(WorkoutSessionsCompanion(
                  endedAt: drift.Value(editingOriginalEndedAt),
                ));
              } else {
                await ref.read(workoutsRepositoryProvider).endSession(widget.session.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Keep Workout'),
          ),
          // 3. Discard: Discard edits or delete new session
          TextButton(
            onPressed: () async {
              if (isEditingPastWorkout) {
                final db = ref.read(appDatabaseProvider);
                final stmt = db.update(db.workoutSessions)
                  ..where((t) => t.id.equals(widget.session.id));
                await stmt.write(WorkoutSessionsCompanion(
                  endedAt: drift.Value(editingOriginalEndedAt),
                ));
                ref.read(editingSessionOriginalEndedAtProvider.notifier).update((state) {
                  final copy = Map<int, DateTime>.from(state);
                  copy.remove(widget.session.id);
                  return copy;
                });
              } else {
                await ref
                    .read(workoutsRepositoryProvider)
                    .deleteSession(widget.session.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
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

  Future<void> _showFinishSummary(
    BuildContext context,
    WidgetRef ref,
    WorkoutSessionData session,
  ) async {
    final editingOriginalEndedAt =
        ref.read(editingSessionOriginalEndedAtProvider)[session.id];
    final nameCtrl = TextEditingController(
      text: session.name ?? 'Awesome Workout',
    );
    final repo = ref.read(workoutsRepositoryProvider);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final currentEndedAt =
              ref.watch(editingSessionOriginalEndedAtProvider)[session.id] ??
                  editingOriginalEndedAt;
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
                        final currentDur =
                            _resolvedEndedAt(session.startedAt, currentEndedAt)
                                .difference(session.startedAt);
                        final newMins = await DurationPickerDialog.show(
                          context,
                          initialMinutes:
                              currentDur.inMinutes > 0 ? currentDur.inMinutes : 45,
                        );
                        if (newMins != null && newMins > 0) {
                          final newEndedAt =
                              session.startedAt.add(Duration(minutes: newMins));
                          ref
                              .read(editingSessionOriginalEndedAtProvider.notifier)
                              .update(
                                (state) => {...state, session.id: newEndedAt},
                              );
                          setStateDialog(() {});
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
              FilledButton(
                onPressed: () async {
                  final finalEndedAt = ref.read(
                        editingSessionOriginalEndedAtProvider,
                      )[session.id] ??
                      editingOriginalEndedAt;
                  final name = nameCtrl.text.trim();
                  await repo.updateSessionName(
                    session.id,
                    name.isEmpty ? 'Workout' : name,
                  );
                  await repo.endSession(session.id, endedAt: finalEndedAt);
                  if (finalEndedAt != null) {
                    ref
                        .read(editingSessionOriginalEndedAtProvider.notifier)
                        .update((state) {
                      final copy = Map<int, DateTime>.from(state);
                      copy.remove(session.id);
                      return copy;
                    });
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (context.mounted) {
                    await WorkoutFinishView.show(context, session.id);
                  }
                },
                child: const Text('Finish'),
              ),
            ],
          );
        },
      ),
    );
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
// Mini Media Pill
// ─────────────────────────────────────────────────────────────────────────────

/// Compact pill in the workout header showing the currently playing track.
/// Animates a music note icon when isPlaying, and taps to open the full
/// [MediaControlsSheet].
class _MediaMiniPill extends StatefulWidget {
  final String track;
  final bool isPlaying;
  final VoidCallback onTap;

  const _MediaMiniPill({
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<_MediaMiniPill> createState() => _MediaMiniPillState();
}

class _MediaMiniPillState extends State<_MediaMiniPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackLabel = widget.track.length > 16
        ? '${widget.track.substring(0, 14)}…'
        : widget.track;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: widget.isPlaying
                  ? _anim
                  : const AlwaysStoppedAnimation(1.0),
              child: Icon(
                Icons.music_note_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              trackLabel,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedExerciseTile extends StatelessWidget {
  final int index;
  final WorkoutExerciseData workoutExercise;
  final List<WorkoutExerciseData> rows;
  final Widget Function(BuildContext context, Widget dragHandle) builder;

  const _LinkedExerciseTile({
    super.key,
    required this.index,
    required this.workoutExercise,
    required this.rows,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final group = workoutExercise.supersetGroup;
    final groupRows = group == null
        ? <WorkoutExerciseData>[]
        : (rows.where((r) => r.supersetGroup == group).toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)));
    final isLinked = groupRows.length > 1;
    final groupIndex = groupRows.indexWhere((r) => r.id == workoutExercise.id);
    final isFirst = groupIndex == 0;
    final isLast = groupIndex == groupRows.length - 1;
    final label = groupRows.length >= 3 ? 'GIANT' : 'SUPER';

    final dragHandle = Tooltip(
      message: 'Hold to reorder',
      child: ReorderableDelayedDragStartListener(
        index: index,
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

    return Stack(
      children: [
        if (isLinked)
          Positioned(
            left: 20,
            top: isFirst ? 34 : 0,
            bottom: isLast ? 34 : 0,
            child: Container(width: 3, color: AppColors.primary),
          ),
        if (isLinked)
          Positioned(
            left: 12,
            top: 27,
            child: Tooltip(
              message: groupRows.length >= 3 ? 'Giant set' : 'Superset',
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
                  '${groupIndex + 1}',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 4, 16, 0),
                  child: Text(
                    '$label SET',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              builder(context, dragHandle),
            ],
          ),
        ),
      ],
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
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
