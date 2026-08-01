import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import 'active_exercise_card.dart';
import 'dynamic_workout_view.dart';
import 'equipment_variant_sheet.dart';
import 'exercise_picker_sheet.dart';
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
                child: Row(
                  children: [
                    Expanded(
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
                                    (session.name != null &&
                                            session.name!.isNotEmpty)
                                        ? session.name!
                                        : 'Workout in progress',
                                    style: theme.textTheme.displayMedium?.copyWith(
                                      fontSize: 20,
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
                          Text(
                            _elapsed(session.startedAt),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Workout settings',
                      onPressed: () => WorkoutSettingsSheet.show(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen),
                      tooltip: 'Dynamic mode',
                      onPressed: () =>
                          ref.read(dynamicWorkoutModeProvider.notifier).state =
                              true,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel workout',
                      onPressed: () => _confirmCancel(context, ref),
                    ),
                  ],
                ),
              ),
            ),
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
                        final result = await ExercisePickerSheet.show(context);
                        if (result == null || !context.mounted) return;
                        final picked = result.exercise;
                        // Skip the equipment sheet when the user already chose
                        // a specific catalog variant in the style chooser.
                        final String? variant;
                        if (result.equipmentAlreadyChosen) {
                          variant = picked.modality;
                        } else {
                          variant = await EquipmentVariantSheet.show(
                            context,
                            picked,
                          );
                        }
                        if (variant == null) return;
                        await repo.addExerciseToSession(
                          sessionId: session.id,
                          exerciseId: picked.id,
                          equipmentVariant: variant,
                        );
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



  String _elapsed(DateTime startedAt) {
    final d = DateTime.now().difference(startedAt);
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
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
          'This deletes the in-progress session and its sets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () async {
              await ref
                  .read(workoutsRepositoryProvider)
                  .deleteSession(widget.session.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Discard',
              style: TextStyle(color: Colors.redAccent),
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
    final nameCtrl = TextEditingController(
      text: session.name ?? 'Awesome Workout',
    );
    final repo = ref.read(workoutsRepositoryProvider);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
            Text('Duration: ${_elapsed(session.startedAt)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Resume'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              await repo.updateSessionName(
                  session.id, name.isEmpty ? 'Workout' : name);
              await repo.endSession(session.id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              // The session is now finished, so this view is about to be
              // swapped out for the landing page — push the celebration off
              // the outer navigator, not the dialog's.
              if (context.mounted) {
                await WorkoutFinishView.show(context, session.id);
              }
            },
            child: const Text('Finish'),
          ),
        ],
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
