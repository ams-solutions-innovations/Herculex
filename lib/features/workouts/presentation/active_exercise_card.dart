import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../profile/domain/profile.dart';
import '../domain/progression_engine.dart';
import '../domain/set_type.dart';
import 'accessory_tray_sheet.dart';
import 'equipment_variant_sheet.dart';
import 'exercise_performance_sheet.dart';
import 'machine_config_sheet.dart';
import 'plate_calculator_sheet.dart';
import 'progression_override_sheet.dart';
import 'rest_timer_controller.dart';
import 'set_type_menu.dart';
import 'smart_substitution_sheet.dart';
import 'workouts_providers.dart';

class ActiveExerciseCard extends ConsumerWidget {
  final WorkoutExerciseData workoutExercise;
  final ExerciseCatalogData exercise;
  final List<WorkoutExerciseData> sessionExercises;
  final List<ExerciseCatalogData> catalogExercises;
  final FocusNode? firstSetFocusNode;
  final bool Function(int workoutExerciseId, int setIndex)? onCompletedSet;
  final VoidCallback onRemove;
  final Widget? dragHandle;

  const ActiveExerciseCard({
    super.key,
    required this.workoutExercise,
    required this.exercise,
    this.sessionExercises = const [],
    this.catalogExercises = const [],
    this.firstSetFocusNode,
    this.onCompletedSet,
    required this.onRemove,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sets = ref.watch(setsForWorkoutExerciseProvider(workoutExercise.id));
    final lastPerformance = ref.watch(lastPerformanceProvider(exercise.id));
    final repo = ref.watch(workoutsRepositoryProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${exercise.primaryMuscle} • ${EquipmentVariantSheet.labelFor(workoutExercise.equipmentVariant ?? exercise.modality)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    _ExerciseAccessoryBadgeRow(
                      workoutExerciseId: workoutExercise.id,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _showMenu(context, ref),
              ),
            ],
          ),
          lastPerformance.maybeWhen(
            data: (allLastSets) {
              if (allLastSets.isEmpty) return const SizedBox.shrink();

              final currentSetsList = sets.value ?? const [];
              final currentSet = currentSetsList.firstWhereOrNull((s) => !s.isCompleted) ?? currentSetsList.lastOrNull;

              List<SetEntryData> filteredSets = [];

              if (currentSet != null) {
                // Find index of currentSet within current sets of the same category (warmup vs working + setType)
                final sameTypeCurrentSets = currentSetsList.where((s) =>
                    s.isWarmup == currentSet.isWarmup &&
                    s.setType == currentSet.setType).toList();
                final typeIndex = sameTypeCurrentSets.indexOf(currentSet);

                // Find matching prior sets of same category
                final matchingPriorSets = allLastSets.where((s) =>
                    s.isWarmup == currentSet.isWarmup &&
                    s.setType == currentSet.setType).toList();

                if (matchingPriorSets.isNotEmpty) {
                  if (typeIndex >= 0 && typeIndex < matchingPriorSets.length) {
                    filteredSets = [matchingPriorSets[typeIndex]];
                  } else {
                    filteredSets = [matchingPriorSets.last];
                  }
                }
              } else {
                // Default: show the first working standard set from prior session
                final standardPriorSets = allLastSets.where((s) =>
                    !s.isWarmup && s.setType == 'standard').toList();
                if (standardPriorSets.isNotEmpty) {
                  filteredSets = [standardPriorSets.first];
                }
              }

              if (filteredSets.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last: ${_formatLast(filteredSets, ref.watch(weightFormatProvider))}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _nextTargetHint(theme, ref, allLastSets),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          _HeaderRow(theme: theme),
          sets.when(
            data: (rows) => Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _SetRow(
                    index: i + 1,
                    set: rows[i],
                    weightFocusNode: i == 0 ? firstSetFocusNode : null,
                    onUpdate: (weight, reps, rpeX10) => repo.updateSet(
                      setId: rows[i].id,
                      weightKg: weight,
                      reps: reps,
                      rpeX10: rpeX10,
                    ),
                    onComplete: (completed) async {
                      await repo.updateSet(
                        setId: rows[i].id,
                        isCompleted: completed,
                      );
                      if (completed) {
                        final advanced =
                            onCompletedSet?.call(
                              workoutExercise.id,
                              rows[i].setIndex,
                            ) ??
                            false;
                        if (!advanced) {
                          final rest =
                              workoutExercise.targetRestSeconds ??
                              exercise.defaultRestSeconds;
                          ref
                              .read(restTimerProvider.notifier)
                              .start(
                                seconds: rest,
                                exerciseName: exercise.name,
                              );
                        }
                      }
                    },
                    onDelete: () => repo.deleteSet(rows[i].id),
                    // One-tap set-type switch (§15, §26).
                    onTypeTap: () async {
                      final sel = await SetTypeMenu.show(
                        context,
                        current: SetType.fromId(rows[i].setType),
                        isWarmup: rows[i].isWarmup,
                      );
                      if (sel != null) {
                        if (sel.delete) {
                          await repo.deleteSet(rows[i].id);
                        } else if (sel.isWarmup != null) {
                          await repo.updateSet(
                            setId: rows[i].id,
                            isWarmup: sel.isWarmup,
                          );
                        } else {
                          await repo.updateSet(
                            setId: rows[i].id,
                            setType: sel.type.id,
                            setTypeMetaJson: sel.metaJson,
                          );
                        }
                      }
                    },
                    // Accessory quick-tray (§5–§8, §26).
                    onAccessories: () =>
                        AccessoryTraySheet.show(context, rows[i]),
                  ),
              ],
            ),
            error: (e, _) => Text('Error: $e'),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () async {
                  // Default new set to last set's values for fast logging.
                  final rows = sets.asData?.value ?? const [];
                  final prev = rows.isNotEmpty ? rows.last : null;
                  final priorFirst = lastPerformance.asData?.value.firstOrNull;

                  double nextWeight = 0.0;
                  int nextReps = 0;

                  if (prev != null) {
                    nextWeight = prev.weightKg;
                    nextReps = prev.reps;
                    // Dynamic drop set weight reduction.
                    if (prev.setType == 'drop' && prev.setTypeMetaJson != null) {
                      try {
                        final meta = jsonDecode(prev.setTypeMetaJson!);
                        final pct = meta['dropPercent'] as int? ?? 20;
                        nextWeight = nextWeight * (1 - (pct / 100));
                        nextWeight = (nextWeight * 2).roundToDouble() / 2;
                      } catch (_) {}
                    }
                  } else if (priorFirst != null) {
                    nextWeight = priorFirst.weightKg;
                    nextReps = priorFirst.reps;
                  }

                  // Weighted bodyweight (§9): snapshot current BW so total load
                  // (added weight + body) feeds volume/1RM correctly.
                  double? bodyweight = prev?.bodyweightKg;
                  if (exercise.supportsWeightedBodyweight && bodyweight == null) {
                    bodyweight = await ref
                        .read(measurementsRepositoryProvider)
                        .latestBodyweightKg();
                  }
                  final newSetId = await repo.addSet(
                    workoutExerciseId: workoutExercise.id,
                    weightKg: nextWeight,
                    reps: nextReps,
                    rpeX10: prev?.rpeX10,
                    isWarmup: prev?.isWarmup ?? false,
                    setType: prev?.setType ?? 'standard',
                    setTypeMetaJson: prev?.setTypeMetaJson,
                    bodyweightKg: bodyweight,
                    chainsKg: prev?.chainsKg,
                  );
                  // Carry the accessory selection forward (§26) so belt/sleeves
                  // don't need re-tapping every set.
                  if (prev != null) {
                    await ref
                        .read(accessoriesRepositoryProvider)
                        .copySetAccessories(fromSetId: prev.id, toSetId: newSetId);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Set'),
              ),
              ?dragHandle,
            ],
          ),
        ],
      ),
    );
  }

  /// Suggested next-workout target (§16): best set from last session run
  /// through the progression engine. Per-exercise override takes priority over
  /// the profile goal.
  Widget _nextTargetHint(
    ThemeData theme,
    WidgetRef ref,
    List<SetEntryData> lastSets,
  ) {
    final workingSets = lastSets.where((s) => !s.isWarmup).toList();
    if (workingSets.isEmpty) {
      return const SizedBox.shrink();
    }
    final best = workingSets.reduce(
      (a, b) => a.weightKg * a.reps >= b.weightKg * b.reps ? a : b,
    );
    final override = ref
        .watch(exerciseProgressionProvider(exercise.id))
        .asData
        ?.value;
    final ProgressionGoal goal;
    final double? weeklyPctOverride;
    if (override != null && override.enabled) {
      goal = ProgressionGoal.values.firstWhere(
        (g) => g.name == override.goal,
        orElse: () => ProgressionGoal.muscleGain,
      );
      weeklyPctOverride = override.weeklyIncreasePct;
    } else {
      final fitnessGoal =
          ref.watch(profileProvider).asData?.value?.goal ??
          FitnessGoal.maintenance;
      goal = switch (fitnessGoal) {
        FitnessGoal.weightLoss => ProgressionGoal.fatLoss,
        FitnessGoal.muscleGain ||
        FitnessGoal.maintenance => ProgressionGoal.muscleGain,
        FitnessGoal.improveHealth => ProgressionGoal.endurance,
      };
      weeklyPctOverride = null;
    }
    final target = ProgressionEngine.suggestNext(
      lastWeightKg: best.weightKg,
      lastReps: best.reps,
      goal: goal,
      equipmentVariant: workoutExercise.equipmentVariant ?? exercise.modality,
      weeklyIncreasePctOverride: weeklyPctOverride,
    );
    if (target.weightKg <= 0 && best.weightKg <= 0) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: target.rationale,
      child: Text(
        'Next: ${ref.watch(weightFormatProvider).format(target.weightKg)} × ${target.reps}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatLast(List<SetEntryData> sets, WeightFormat fmt) {
    return sets
        .map((s) {
          final rpe = s.rpeX10 != null
              ? ' @${(s.rpeX10! / 10).toStringAsFixed(1)}'
              : '';
          return '${fmt.format(s.weightKg)} × ${s.reps}$rpe';
        })
        .join(' • ');
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final isMachine = (workoutExercise.equipmentVariant ?? exercise.modality)
        .startsWith('machine');
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(_linkTitle()),
              subtitle: Text(_linkSubtitle()),
              onTap: () {
                Navigator.pop(context);
                _showLinkSheet(context, ref);
              },
            ),
            if (workoutExercise.supersetGroup != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Remove from linked set'),
                subtitle: const Text('This exercise becomes standalone'),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(workoutsRepositoryProvider)
                      .unlinkWorkoutExercise(workoutExercise.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('View performance'),
              subtitle: const Text('PRs per equipment & accessory combo'),
              onTap: () {
                Navigator.pop(context);
                ExercisePerformanceSheet.show(context, exercise);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('Change equipment'),
              subtitle: Text(
                EquipmentVariantSheet.labelFor(
                  workoutExercise.equipmentVariant ?? exercise.modality,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                final variant = await EquipmentVariantSheet.show(
                  context,
                  exercise,
                );
                if (variant != null) {
                  await ref
                      .read(workoutsRepositoryProvider)
                      .setEquipmentVariant(
                        workoutExerciseId: workoutExercise.id,
                        equipmentVariant: variant,
                      );
                }
              },
            ),
            if (isMachine || workoutExercise.machineConfigJson != null)
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Machine settings'),
                subtitle: const Text('Seat, angle, lever position…'),
                onTap: () {
                  Navigator.pop(context);
                  final gymId = ref
                      .read(activeSessionProvider)
                      .asData
                      ?.value
                      ?.gymId;
                  MachineConfigSheet.show(
                    context,
                    workoutExercise: workoutExercise,
                    gymId: gymId,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Set progression goal'),
              subtitle: const Text('Override rep range & weekly load increase'),
              onTap: () {
                Navigator.pop(context);
                ProgressionOverrideSheet.show(
                  context,
                  exerciseId: exercise.id,
                  exerciseName: exercise.name,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Substitute exercise'),
              onTap: () {
                Navigator.pop(context);
                SmartSubstitutionSheet.show(
                  context,
                  workoutExercise: workoutExercise,
                  originalExercise: exercise,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove exercise'),
              onTap: () {
                Navigator.pop(context);
                onRemove();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _linkTitle() {
    final linkedCount = sessionExercises
        .where((e) => e.supersetGroup == workoutExercise.supersetGroup)
        .length;
    if (workoutExercise.supersetGroup == null || linkedCount <= 1) {
      return 'Link as superset';
    }
    return linkedCount >= 3 ? 'Edit giant set' : 'Edit superset';
  }

  String _linkSubtitle() {
    final linkedCount = sessionExercises
        .where((e) => e.supersetGroup == workoutExercise.supersetGroup)
        .length;
    if (workoutExercise.supersetGroup == null || linkedCount <= 1) {
      return 'Pair with another exercise';
    }
    return 'Linked with ${linkedCount - 1} other exercise${linkedCount == 2 ? '' : 's'}';
  }

  void _showLinkSheet(BuildContext context, WidgetRef ref) {
    final candidates =
        sessionExercises.where((we) => we.id != workoutExercise.id).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.link),
              title: Text('Connect exercises'),
              subtitle: Text(
                '2 exercises = superset, 3+ exercises = giant set',
              ),
            ),
            if (candidates.isEmpty)
              const ListTile(title: Text('Add another exercise first'))
            else
              for (final candidate in candidates)
                ListTile(
                  leading: Icon(
                    candidate.supersetGroup == workoutExercise.supersetGroup &&
                            candidate.supersetGroup != null
                        ? Icons.check_circle
                        : Icons.add_link,
                  ),
                  title: Text(_exerciseName(candidate.exerciseId)),
                  subtitle: Text(
                    candidate.supersetGroup == workoutExercise.supersetGroup &&
                            candidate.supersetGroup != null
                        ? 'Already connected'
                        : 'Connect to this exercise',
                  ),
                  onTap: () async {
                    await ref
                        .read(workoutsRepositoryProvider)
                        .linkWorkoutExercises(
                          sessionId: workoutExercise.sessionId,
                          sourceWorkoutExerciseId: workoutExercise.id,
                          targetWorkoutExerciseId: candidate.id,
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
          ],
        ),
      ),
    );
  }

  String _exerciseName(int exerciseId) {
    return catalogExercises.firstWhereOrNull((e) => e.id == exerciseId)?.name ??
        'Exercise #$exerciseId';
  }
}

class _HeaderRow extends ConsumerWidget {
  final ThemeData theme;
  const _HeaderRow({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.secondary,
      letterSpacing: 1.0,
    );
    // The weight column is labelled with whatever unit the fields expect.
    final unit = ref.watch(weightFormatProvider).suffix.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('SET', style: s)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(unit, style: s, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('REPS', style: s, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('RPE', style: s, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 78),
        ],
      ),
    );
  }
}

class _SetRow extends ConsumerStatefulWidget {
  final int index;
  final SetEntryData set;
  final FocusNode? weightFocusNode;
  final Future<void> Function(double? weight, int? reps, int? rpeX10) onUpdate;
  final Future<void> Function(bool completed) onComplete;
  final VoidCallback onDelete;
  final VoidCallback onTypeTap;
  final VoidCallback onAccessories;

  const _SetRow({
    required this.index,
    required this.set,
    this.weightFocusNode,
    required this.onUpdate,
    required this.onComplete,
    required this.onDelete,
    required this.onTypeTap,
    required this.onAccessories,
  });

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late final TextEditingController _rpe;

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(text: _fmtWeight(widget.set.weightKg));
    _reps = TextEditingController(
      text: widget.set.reps == 0 ? '' : widget.set.reps.toString(),
    );
    _rpe = TextEditingController(
      text: widget.set.rpeX10 == null
          ? ''
          : (widget.set.rpeX10! / 10).toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(covariant _SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync if upstream value diverged (e.g. duplicated from prev set).
    if (oldWidget.set.weightKg != widget.set.weightKg) {
      _weight.text = _fmtWeight(widget.set.weightKg);
    }
    if (oldWidget.set.reps != widget.set.reps) {
      _reps.text = widget.set.reps == 0 ? '' : widget.set.reps.toString();
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _rpe.dispose();
    super.dispose();
  }

  /// Sets are stored in kilograms; the field shows and accepts the user's
  /// chosen unit, so an imperial user types and reads pounds throughout.
  WeightFormat get _fmt => ref.read(weightFormatProvider);

  String _fmtWeight(double kg) => kg == 0 ? '' : _fmt.formatValue(kg);

  /// Set index cell: warmups show 'W', non-standard set types show their
  /// badge ('D' drop, 'RP' rest-pause, …), plain sets show the number.
  String _indexLabel() {
    if (widget.set.isWarmup) return 'W';
    final type = SetType.fromId(widget.set.setType);
    final badge = SetTypeMenu.badge(type);
    return badge.isEmpty ? '${widget.index}' : badge;
  }

  Color _indexColor() {
    if (widget.set.isWarmup) return AppColors.outline;
    if (SetType.fromId(widget.set.setType) != SetType.standard) {
      return AppColors.primary;
    }
    return AppColors.onSurface;
  }

  void _commit() {
    final entered = double.tryParse(_weight.text);
    final r = int.tryParse(_reps.text);
    final rpe = double.tryParse(_rpe.text);
    // Convert the typed display value back to kilograms before it reaches
    // the repository — storage is always metric.
    widget.onUpdate(entered == null ? null : _fmt.toKg(entered), r,
        rpe == null ? null : (rpe * 10).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = widget.set.isCompleted;
    final color = isCompleted
        ? AppColors.primary.withValues(alpha: 0.08)
        : Colors.transparent;

    final attachedAccs =
        ref.watch(setAccessoriesProvider(widget.set.id)).asData?.value ??
        const [];
    final attachedBands =
        ref.watch(setBandsProvider(widget.set.id)).asData?.value ?? const [];
    final catalogAccs =
        ref.watch(accessoriesProvider).asData?.value ?? const [];
    final catalogBands = ref.watch(bandsProvider).asData?.value ?? const [];

    final activeTags = <String>[];
    for (final sa in attachedAccs) {
      final acc = catalogAccs.firstWhereOrNull((a) => a.id == sa.accessoryId);
      if (acc != null) {
        activeTags.add(acc.name);
      }
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
    if (widget.set.chainsKg != null && widget.set.chainsKg! > 0) {
      final cVal = widget.set.chainsKg!;
      final cFmt = cVal.truncateToDouble() == cVal
          ? cVal.toStringAsFixed(0)
          : cVal.toStringAsFixed(1);
      activeTags.add('Chains (${cFmt}kg)');
    }

    return Dismissible(
      key: ValueKey('set_${widget.set.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.redAccent.withValues(alpha: 0.85),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Tapping the set index switches the set type (§15, §26).
                InkWell(
                  onTap: widget.onTypeTap,
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 28,
                    height: 32,
                    child: Center(
                      child: Text(
                        _indexLabel(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _indexColor(),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onLongPress: () {
                      Haptics.medium();
                      final kg = double.tryParse(_weight.text);
                      final weightKg = kg != null ? _fmt.toKg(kg) : null;
                      PlateCalculatorSheet.show(
                        context,
                        weightKg: weightKg,
                      );
                    },
                    child: _numberField(
                      _weight,
                      decimal: true,
                      fillColor: Colors.blue.withValues(alpha: 0.15),
                      focusNode: widget.weightFocusNode,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    _reps,
                    fillColor: Colors.orange.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _rpeField(context)),
                // Accessory quick-tray (§26): belt/bands/chains without leaving
                // the set.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  icon: Icon(
                    Icons.construction,
                    size: 18,
                    color: activeTags.isNotEmpty
                        ? AppColors.primary
                        : AppColors.outline,
                  ),
                  tooltip: activeTags.isNotEmpty
                      ? 'Accessories: ${activeTags.join(", ")}'
                      : 'Accessories',
                  onPressed: widget.onAccessories,
                ),
                GestureDetector(
                  onTap: () {
                    Haptics.medium();
                    _commit();
                    widget.onComplete(!isCompleted);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? AppColors.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: isCompleted
                              ? AppColors.primary
                              : AppColors.outline,
                          width: 2,
                        ),
                      ),
                      child: isCompleted
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (activeTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2, bottom: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final tag in activeTags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 10,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              tag,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (SetType.fromId(widget.set.setType) == SetType.myoReps)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2, bottom: 4),
                child: Builder(
                  builder: (context) {
                    final meta = widget.set.setTypeMetaJson != null
                        ? jsonDecode(widget.set.setTypeMetaJson!)
                        : <String, dynamic>{};
                    final miniSets =
                        (meta['miniSets'] as List<dynamic>?)?.cast<int>() ?? [];
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int i = 0; i < miniSets.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${miniSets[i]} reps',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        InkWell(
                          onTap: () async {
                            final reps = await _askForMiniSetReps(context);
                            if (reps != null && reps > 0) {
                              final newMini = List<int>.from(miniSets)
                                ..add(reps);
                              meta['miniSets'] = newMini;
                              await ref
                                  .read(workoutsRepositoryProvider)
                                  .updateSet(
                                    setId: widget.set.id,
                                    setTypeMetaJson: jsonEncode(meta),
                                  );
                              ref
                                  .read(restTimerProvider.notifier)
                                  .start(
                                    seconds: 15,
                                    exerciseName: 'Myo-rep Rest',
                                  );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Mini Set',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<int?> _askForMiniSetReps(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Mini-Set'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Reps (e.g. 3)'),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
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

  Widget _numberField(
    TextEditingController ctrl, {
    bool decimal = false,
    Color? fillColor,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      onEditingComplete: _commit,
      onTapOutside: (_) => _commit(),
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: false,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        filled: true,
        fillColor: fillColor ?? AppColors.surfaceContainer,
        // Pill-shaped set inputs (stadium border).
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _rpeField(BuildContext context) {
    final theme = Theme.of(context);
    final val = _rpe.text.isEmpty ? null : double.tryParse(_rpe.text);
    return InkWell(
      onTap: () => _showRpeGrid(context),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          val != null ? val.toStringAsFixed(1) : 'RPE',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: val != null ? FontWeight.bold : FontWeight.normal,
            color: val != null ? Colors.purple : AppColors.secondary,
          ),
        ),
      ),
    );
  }

  Future<void> _showRpeGrid(BuildContext context) async {
    final res = await showModalBottomSheet<double?>(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select RPE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (double i = 5.0; i <= 10.0; i += 0.5)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, i),
                      child: Container(
                        width: 55,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          i.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx, -1.0),
                child: const Text('Clear RPE'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (res != null) {
      if (res < 0) {
        _rpe.clear();
      } else {
        _rpe.text = res.toStringAsFixed(1);
      }
      _commit();
    }
  }
}

class _ExerciseAccessoryBadgeRow extends ConsumerWidget {
  final int workoutExerciseId;
  const _ExerciseAccessoryBadgeRow({required this.workoutExerciseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sets =
        ref
            .watch(setsForWorkoutExerciseProvider(workoutExerciseId))
            .asData
            ?.value ??
        const [];
    if (sets.isEmpty) return const SizedBox.shrink();

    final catalogAccs =
        ref.watch(accessoriesProvider).asData?.value ?? const [];
    final catalogBands = ref.watch(bandsProvider).asData?.value ?? const [];

    final allTags = <String>{};
    for (final s in sets) {
      final attachedAccs =
          ref.watch(setAccessoriesProvider(s.id)).asData?.value ?? const [];
      final attachedBands =
          ref.watch(setBandsProvider(s.id)).asData?.value ?? const [];
      for (final sa in attachedAccs) {
        final acc = catalogAccs.firstWhereOrNull((a) => a.id == sa.accessoryId);
        if (acc != null) allTags.add(acc.name);
      }
      for (final sb in attachedBands) {
        final band = catalogBands.firstWhereOrNull((b) => b.id == sb.bandId);
        if (band != null) allTags.add(band.name);
      }
      if (s.chainsKg != null && s.chainsKg! > 0) {
        allTags.add('Chains');
      }
    }

    if (allTags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final tag in allTags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction, size: 10, color: AppColors.primary),
                  const SizedBox(width: 3),
                  Text(
                    tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
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
