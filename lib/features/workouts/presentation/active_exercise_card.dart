import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../profile/domain/profile.dart';
import '../../reps/domain/rep_suggestion.dart';
import '../../reps/domain/rep_tracking_eligibility.dart';
import '../../reps/presentation/rep_review_sheet.dart';
import '../../reps/presentation/rep_tracker_panel.dart';
import '../../reps/presentation/rep_tracking_providers.dart';
import '../data/workouts_repository.dart';
import '../domain/drop_set_rounding.dart';
import '../domain/progression_engine.dart';
import '../domain/set_type.dart';
import 'accessory_tray_sheet.dart';
import 'down_set_config_sheet.dart';
import 'equipment_variant_sheet.dart';
import 'exercise_performance_sheet.dart';
import 'machine_config_sheet.dart';
import 'plate_calculator_sheet.dart';
import 'progression_override_sheet.dart';
import 'rest_timer_controller.dart';
import 'set_type_menu.dart';
import 'smart_substitution_sheet.dart';
import 'workout_settings_sheet.dart';
import 'workouts_providers.dart';

class ActiveExerciseCard extends ConsumerStatefulWidget {
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
  ConsumerState<ActiveExerciseCard> createState() => _ActiveExerciseCardState();
}

class _ActiveExerciseCardState extends ConsumerState<ActiveExerciseCard> {
  final GlobalKey _cardKey = GlobalKey();
  static const _collapsedSetLimit = 5;
  bool _setsExpanded = false;

  /// The most recent [RepSuggestion] `RepTrackerPanel` has produced for a
  /// given set-entry id, awaiting the user's own tap on that set's
  /// completion checkmark. Nothing here is written to the database — see
  /// the `onComplete` handler below, which is the only place that opens
  /// `RepReviewSheet` and the only place `onConfirm` is supplied.
  final Map<int, RepSuggestion> _pendingSuggestions = {};

  @override
  Widget build(BuildContext context) {
    final workoutExercise = widget.workoutExercise;
    final exercise = widget.exercise;
    final theme = Theme.of(context);
    final sets = ref.watch(setsForWorkoutExerciseProvider(workoutExercise.id));
    final lastPerformance = ref.watch(lastPerformanceProvider(exercise.id));
    final repo = ref.watch(workoutsRepositoryProvider);
    final weightFmt = ref.watch(weightFormatProvider);
    final hintMode = ref.watch(performanceHintModeProvider);
    final isBodyweight = exercise.modality == 'bodyweight';
    final totalReps = isBodyweight
        ? (sets.asData?.value ?? const <SetEntryData>[])
              .where((r) => r.isCompleted)
              .fold<int>(0, (sum, r) => sum + r.reps)
        : 0;

    return Container(
      key: _cardKey,
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
            data: (snapshot) {
              final allLastSets = snapshot?.sets ?? const <SetEntryData>[];
              if (allLastSets.isEmpty) return const SizedBox.shrink();

              final currentRows = sets.asData?.value ?? const <SetEntryData>[];
              final lastText = _formatLast(currentRows, allLastSets, weightFmt);
              if (hintMode == PerformanceHintMode.last && lastText.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: hintMode == PerformanceHintMode.last
                    ? Text(
                        '${_lastLabel(snapshot)}: $lastText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : _nextTargetHint(theme, ref, allLastSets),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          if (isBodyweight && totalReps > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat, size: 14, color: AppColors.secondary),
                  const SizedBox(width: 4),
                  Text(
                    '$totalReps reps total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _HeaderRow(theme: theme),
          sets.when(
            data: (rows) {
              final allLastSets =
                  lastPerformance.asData?.value?.sets ?? const <SetEntryData>[];
              // Down Sets are numbered D1, D2, … across a run of consecutive
              // down-set rows; any other set type resets the count.
              final downSetOrdinals = <int>[];
              var downSetChain = 0;
              for (final r in rows) {
                downSetChain = r.setType == 'down_sets' ? downSetChain + 1 : 0;
                downSetOrdinals.add(downSetChain);
              }
              // Collapse long set lists (item 7) but never hide the set the
              // user is about to log.
              final collapse =
                  !_setsExpanded && rows.length > _collapsedSetLimit;
              List<int> visibleIndices;
              if (collapse) {
                final nextIncompleteIndex = rows.indexWhere(
                  (r) => !r.isCompleted,
                );
                final indices = <int>{
                  for (var k = 0; k < _collapsedSetLimit; k++) k,
                };
                if (nextIncompleteIndex >= _collapsedSetLimit) {
                  indices.add(nextIncompleteIndex);
                }
                visibleIndices = indices.toList()..sort();
              } else {
                visibleIndices = [for (var k = 0; k < rows.length; k++) k];
              }
              return Column(
                children: [
                  for (final i in visibleIndices)
                    _SetRow(
                      index: i + 1,
                      set: rows[i],
                      downSetOrdinal: downSetOrdinals[i],
                      priorSet: _findPriorSet(rows[i], i, rows, allLastSets),
                      microLabelText: _microLabelFor(
                        ref,
                        rows,
                        allLastSets,
                        downSetOrdinals,
                        i,
                        hintMode,
                        weightFmt,
                      ),
                      weightFocusNode: i == 0 ? widget.firstSetFocusNode : null,
                      cardKey: _cardKey,
                      onUpdate: (weight, reps, rpeX10, clearRpe) =>
                          repo.updateSet(
                            setId: rows[i].id,
                            weightKg: weight,
                            reps: reps,
                            rpeX10: rpeX10,
                            clearRpe: clearRpe,
                          ),
                      onComplete: (completed) async {
                        // A pending suggestion for this exact set entry means
                        // the tracker proposed a count for it — the review
                        // sheet is the *only* place that can turn "completed"
                        // into a write, and only after the user's own Save
                        // tap (REP-03). Dismissing it leaves the set and the
                        // observation table both untouched.
                        final suggestion =
                            completed ? _pendingSuggestions[rows[i].id] : null;
                        var saved = suggestion == null;
                        if (suggestion != null) {
                          if (!context.mounted) return;
                          await RepReviewSheet.show(
                            context,
                            suggestion: suggestion,
                            sessionId: workoutExercise.sessionId,
                            setEntryId: rows[i].id,
                            onConfirm: (reps, rpeX10) async {
                              await repo.updateSet(
                                setId: rows[i].id,
                                reps: reps,
                                rpeX10: rpeX10,
                                isCompleted: true,
                              );
                              saved = true;
                            },
                          );
                          if (mounted) {
                            setState(
                              () => _pendingSuggestions.remove(rows[i].id),
                            );
                          }
                          if (!saved) return;
                        } else {
                          await repo.updateSet(
                            setId: rows[i].id,
                            isCompleted: completed,
                          );
                        }
                        if (completed) {
                          final allSetsDone = rows
                              .where((r) => r.id != rows[i].id)
                              .every((r) => r.isCompleted);
                          final advanced = allSetsDone
                              ? (widget.onCompletedSet?.call(
                                      workoutExercise.id,
                                      rows[i].setIndex,
                                    ) ??
                                    false)
                              : false;
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
                      // Down Set auto-fill wizard: turns the long-pressed row
                      // into the chain's first set and appends the rest.
                      onDownSetChain: (result) async {
                        final metaJson = jsonEncode({
                          'startReps': result.firstReps,
                          'decrement': 1,
                        });
                        await repo.updateSet(
                          setId: rows[i].id,
                          weightKg: result.weightKg,
                          reps: result.firstReps,
                          setType: 'down_sets',
                          setTypeMetaJson: metaJson,
                        );
                        var reps = result.firstReps;
                        while (reps > result.stopReps) {
                          reps -= 1;
                          await repo.addSet(
                            workoutExerciseId: workoutExercise.id,
                            weightKg: result.weightKg,
                            reps: reps,
                            isWarmup: false,
                            setType: 'down_sets',
                            setTypeMetaJson: metaJson,
                          );
                        }
                      },
                      // Accessory quick-tray (§5–§8, §26).
                      onAccessories: () =>
                          AccessoryTraySheet.show(context, rows[i]),
                    ),
                  if (rows.length > _collapsedSetLimit)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _setsExpanded = !_setsExpanded),
                        child: Text(
                          _setsExpanded ? 'Show less' : 'Show all (${rows.length})',
                        ),
                      ),
                    ),
                  // Additive insertion (Task 2): a non-eligible exercise, or
                  // one with no incomplete set left, renders nothing extra
                  // here — the card is identical to before the phase.
                  if (isEligible(exercise.slug) && _trackedSetId(rows) != null)
                    RepTrackerPanel(
                      key: ValueKey('rep_tracker_${workoutExercise.id}'),
                      exerciseSlug: exercise.slug!,
                      sessionId: workoutExercise.sessionId,
                      setEntryId: _trackedSetId(rows)!,
                      onSuggestion: (s) {
                        final id = _trackedSetId(rows);
                        if (id == null) return;
                        setState(() => _pendingSuggestions[id] = s);
                      },
                    ),
                ],
              );
            },
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
                  final priorFirst =
                      lastPerformance.asData?.value?.sets.firstOrNull;

                  double nextWeight = 0.0;
                  int nextReps = 0;

                  if (prev != null) {
                    nextWeight = prev.weightKg;
                    nextReps = prev.reps;
                    // Dynamic drop set weight reduction.
                    if (prev.setType == 'drop' &&
                        prev.setTypeMetaJson != null) {
                      try {
                        final meta = jsonDecode(prev.setTypeMetaJson!);
                        final pct = meta['dropPercent'] as int? ?? 20;
                        nextWeight = nextWeight * (1 - (pct / 100));
                        final stepKg = dropSetRoundingStepKg(
                          workoutExercise.equipmentVariant ??
                              exercise.modality,
                        );
                        nextWeight =
                            (nextWeight / stepKg).roundToDouble() * stepKg;
                      } catch (_) {}
                    }
                    // Down Sets: same weight, one fewer rep each extra set.
                    if (prev.setType == 'down_sets') {
                      nextReps = prev.reps > 1 ? prev.reps - 1 : 1;
                    }
                  } else if (priorFirst != null) {
                    nextWeight = priorFirst.weightKg;
                    nextReps = priorFirst.reps;
                  }

                  // Weighted bodyweight (§9): snapshot current BW so total load
                  // (added weight + body) feeds volume/1RM correctly.
                  double? bodyweight = prev?.bodyweightKg;
                  if (exercise.supportsWeightedBodyweight &&
                      bodyweight == null) {
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
                        .copySetAccessories(
                          fromSetId: prev.id,
                          toSetId: newSetId,
                        );
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Set'),
              ),
              ?widget.dragHandle,
            ],
          ),
        ],
      ),
    );
  }

  /// The set entry `RepTrackerPanel` tracks for this exercise card: the
  /// next incomplete set, or null once every set is done.
  int? _trackedSetId(List<SetEntryData> rows) {
    final i = rows.indexWhere((r) => !r.isCompleted);
    return i < 0 ? null : rows[i].id;
  }

  SetEntryData? _findPriorSet(
    SetEntryData currentSet,
    int index,
    List<SetEntryData> allCurrentSets,
    List<SetEntryData> allLastSets,
  ) {
    if (allLastSets.isEmpty) return null;
    final sameTypeCurrent = allCurrentSets
        .where(
          (s) =>
              s.isWarmup == currentSet.isWarmup &&
              s.setType == currentSet.setType,
        )
        .toList();
    final subIdx = sameTypeCurrent.indexOf(currentSet);
    final sameTypePrior = allLastSets
        .where(
          (s) =>
              s.isWarmup == currentSet.isWarmup &&
              s.setType == currentSet.setType,
        )
        .toList();
    if (sameTypePrior.isNotEmpty) {
      if (subIdx >= 0 && subIdx < sameTypePrior.length) {
        return sameTypePrior[subIdx];
      }
      return sameTypePrior.last;
    }
    if (index < allLastSets.length) return allLastSets[index];
    return allLastSets.lastOrNull;
  }

  /// Progression goal + weekly-increase override to feed [ProgressionEngine],
  /// shared by the card-level and per-row "Next" hints. Per-exercise override
  /// takes priority over the profile goal.
  ({ProgressionGoal goal, double? weeklyPctOverride}) _progressionGoal(
    WidgetRef ref,
  ) {
    final override = ref
        .watch(exerciseProgressionProvider(widget.exercise.id))
        .asData
        ?.value;
    if (override != null && override.enabled) {
      final goal = ProgressionGoal.values.firstWhere(
        (g) => g.name == override.goal,
        orElse: () => ProgressionGoal.muscleGain,
      );
      return (goal: goal, weeklyPctOverride: override.weeklyIncreasePct);
    }
    final fitnessGoal =
        ref.watch(profileProvider).asData?.value?.goal ??
        FitnessGoal.maintenance;
    final goal = switch (fitnessGoal) {
      FitnessGoal.weightLoss => ProgressionGoal.fatLoss,
      FitnessGoal.muscleGain ||
      FitnessGoal.maintenance => ProgressionGoal.muscleGain,
      FitnessGoal.improveHealth => ProgressionGoal.endurance,
    };
    return (goal: goal, weeklyPctOverride: null);
  }

  /// Suggested next-workout target (§16): best set from last session run
  /// through the progression engine.
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
    final settings = _progressionGoal(ref);
    final target = ProgressionEngine.suggestNext(
      lastWeightKg: best.weightKg,
      lastReps: best.reps,
      goal: settings.goal,
      equipmentVariant: widget.workoutExercise.equipmentVariant ?? widget.exercise.modality,
      weeklyIncreasePctOverride: settings.weeklyPctOverride,
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

  /// Per-row micro-label under a set (item 1): a compact "Down: X-Y" once per
  /// down-set chain, otherwise a position-matched Last/Next hint driven by
  /// the [PerformanceHintMode] setting.
  String? _microLabelFor(
    WidgetRef ref,
    List<SetEntryData> rows,
    List<SetEntryData> allLastSets,
    List<int> downSetOrdinals,
    int i,
    PerformanceHintMode hintMode,
    WeightFormat weightFmt,
  ) {
    if (downSetOrdinals[i] > 0) {
      if (downSetOrdinals[i] != 1) return null;
      var e = i;
      while (e + 1 < rows.length &&
          downSetOrdinals[e + 1] == downSetOrdinals[e] + 1) {
        e++;
      }
      return 'Down: ${rows[i].reps}-${rows[e].reps}';
    }
    final prior = _findPriorSet(rows[i], i, rows, allLastSets);
    if (prior == null) return null;
    if (hintMode == PerformanceHintMode.last) {
      return 'Last: ${weightFmt.format(prior.weightKg)} × ${prior.reps}';
    }
    if (prior.isWarmup) return null;
    final settings = _progressionGoal(ref);
    final target = ProgressionEngine.suggestNext(
      lastWeightKg: prior.weightKg,
      lastReps: prior.reps,
      goal: settings.goal,
      equipmentVariant:
          widget.workoutExercise.equipmentVariant ?? widget.exercise.modality,
      weeklyIncreasePctOverride: settings.weeklyPctOverride,
    );
    if (target.weightKg <= 0 && prior.weightKg <= 0) return null;
    return 'Next: ${weightFmt.format(target.weightKg)} × ${target.reps}';
  }

  String _formatLast(
    List<SetEntryData> currentRows,
    List<SetEntryData> allLastSets,
    WeightFormat fmt,
  ) {
    if (allLastSets.isEmpty) return '';

    SetEntryData? prior;
    if (currentRows.isEmpty) {
      prior = allLastSets.firstOrNull;
    } else {
      var activeIndex = currentRows.indexWhere((r) => !r.isCompleted);
      if (activeIndex == -1) {
        activeIndex = currentRows.length - 1;
      }
      if (activeIndex >= 0 && activeIndex < currentRows.length) {
        prior = _findPriorSet(
          currentRows[activeIndex],
          activeIndex,
          currentRows,
          allLastSets,
        );
      } else {
        prior = activeIndex < allLastSets.length
            ? allLastSets[activeIndex]
            : allLastSets.lastOrNull;
      }
    }

    if (prior == null) return '';

    final rpe = prior.rpeX10 != null
        ? ' @${(prior.rpeX10! / 10).toStringAsFixed(1)}'
        : '';
    return '${fmt.format(prior.weightKg)} × ${prior.reps}$rpe';
  }

  String _lastLabel(LastPerformanceSnapshot? snapshot) {
    final currentVariant =
        widget.workoutExercise.equipmentVariant ?? widget.exercise.modality;
    final priorVariant = snapshot?.equipmentVariant;
    if (priorVariant == null ||
        priorVariant.isEmpty ||
        priorVariant == currentVariant) {
      return 'Last';
    }
    return 'Last on ${EquipmentVariantSheet.labelFor(priorVariant)}';
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final isMachine = (widget.workoutExercise.equipmentVariant ?? widget.exercise.modality)
        .startsWith('machine');
    final slug = widget.exercise.slug;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEligible(slug)) _RepTrackingMenuTile(exerciseSlug: slug!),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(_linkTitle()),
              subtitle: Text(_linkSubtitle()),
              onTap: () {
                Navigator.pop(context);
                _showLinkSheet(context, ref);
              },
            ),
            if (widget.workoutExercise.supersetGroup != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Remove from linked set'),
                subtitle: const Text('This exercise becomes standalone'),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(workoutsRepositoryProvider)
                      .unlinkWorkoutExercise(widget.workoutExercise.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('View performance'),
              subtitle: const Text('PRs per equipment & accessory combo'),
              onTap: () {
                Navigator.pop(context);
                ExercisePerformanceSheet.show(context, widget.exercise);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('Change equipment'),
              subtitle: Text(
                EquipmentVariantSheet.labelFor(
                  widget.workoutExercise.equipmentVariant ?? widget.exercise.modality,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                final variant = await EquipmentVariantSheet.show(
                  context,
                  widget.exercise,
                );
                if (variant != null) {
                  await ref
                      .read(workoutsRepositoryProvider)
                      .setEquipmentVariant(
                        workoutExerciseId: widget.workoutExercise.id,
                        equipmentVariant: variant,
                      );
                }
              },
            ),
            if (isMachine || widget.workoutExercise.machineConfigJson != null)
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
                    workoutExercise: widget.workoutExercise,
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
                  exerciseId: widget.exercise.id,
                  exerciseName: widget.exercise.name,
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
                  workoutExercise: widget.workoutExercise,
                  originalExercise: widget.exercise,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove exercise'),
              onTap: () {
                Navigator.pop(context);
                widget.onRemove();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _linkTitle() {
    final linkedCount = widget.sessionExercises
        .where((e) => e.supersetGroup == widget.workoutExercise.supersetGroup)
        .length;
    if (widget.workoutExercise.supersetGroup == null || linkedCount <= 1) {
      return 'Link as superset';
    }
    return linkedCount >= 3 ? 'Edit giant set' : 'Edit superset';
  }

  String _linkSubtitle() {
    final linkedCount = widget.sessionExercises
        .where((e) => e.supersetGroup == widget.workoutExercise.supersetGroup)
        .length;
    if (widget.workoutExercise.supersetGroup == null || linkedCount <= 1) {
      return 'Pair with another exercise';
    }
    return 'Linked with ${linkedCount - 1} other exercise${linkedCount == 2 ? '' : 's'}';
  }

  void _showLinkSheet(BuildContext context, WidgetRef ref) {
    final candidates =
        widget.sessionExercises.where((we) => we.id != widget.workoutExercise.id).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    // Hard cap of 5 linked exercises per group (item 9): once the current
    // group is full, unconnected candidates can no longer be added.
    final currentGroupSize = widget.workoutExercise.supersetGroup == null
        ? 1
        : widget.sessionExercises
              .where(
                (e) => e.supersetGroup == widget.workoutExercise.supersetGroup,
              )
              .length;
    final atCap = currentGroupSize >= 5;

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
                _linkCandidateTile(ctx, ref, candidate, atCap),
          ],
        ),
      ),
    );
  }

  String _exerciseName(int exerciseId) {
    return widget.catalogExercises.firstWhereOrNull((e) => e.id == exerciseId)?.name ??
        'Exercise #$exerciseId';
  }

  Widget _linkCandidateTile(
    BuildContext ctx,
    WidgetRef ref,
    WorkoutExerciseData candidate,
    bool atCap,
  ) {
    final alreadyConnected =
        candidate.supersetGroup == widget.workoutExercise.supersetGroup &&
        candidate.supersetGroup != null;
    final disabled = atCap && !alreadyConnected;
    return ListTile(
      enabled: !disabled,
      leading: Icon(alreadyConnected ? Icons.check_circle : Icons.add_link),
      title: Text(_exerciseName(candidate.exerciseId)),
      subtitle: Text(
        alreadyConnected
            ? 'Already connected'
            : disabled
            ? 'Group is full (max 5)'
            : 'Connect to this exercise',
      ),
      onTap: disabled
          ? null
          : () async {
              await ref
                  .read(workoutsRepositoryProvider)
                  .linkWorkoutExercises(
                    sessionId: widget.workoutExercise.sessionId,
                    sourceWorkoutExerciseId: widget.workoutExercise.id,
                    targetWorkoutExerciseId: candidate.id,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
    );
  }
}

class _HeaderRow extends ConsumerWidget {
  final ThemeData theme;
  const _HeaderRow({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.secondary,
      letterSpacing: 0.8,
    );
    // The weight column is labelled with whatever unit the fields expect.
    final unit = ref.watch(weightFormatProvider).suffix.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(child: Text('SET', style: s)),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text(unit, style: s, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('REPS', style: s, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('RPE', style: s, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 64),
        ],
      ),
    );
  }
}



class _SetRow extends ConsumerStatefulWidget {
  final int index;
  final SetEntryData set;
  final int downSetOrdinal;
  final SetEntryData? priorSet;
  final String? microLabelText;
  final FocusNode? weightFocusNode;
  final GlobalKey? cardKey;
  final Future<void> Function(
    double? weight,
    int? reps,
    int? rpeX10,
    bool clearRpe,
  )
  onUpdate;
  final Future<void> Function(bool completed) onComplete;
  final VoidCallback onDelete;
  final VoidCallback onTypeTap;
  final Future<void> Function(DownSetChainResult result) onDownSetChain;
  final VoidCallback onAccessories;

  const _SetRow({
    required this.index,
    required this.set,
    this.downSetOrdinal = 0,
    this.priorSet,
    this.microLabelText,
    this.weightFocusNode,
    this.cardKey,
    required this.onUpdate,
    required this.onComplete,
    required this.onDelete,
    required this.onTypeTap,
    required this.onDownSetChain,
    required this.onAccessories,
  });

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late final TextEditingController _rpe;
  late final FocusNode _fallbackWeightFocusNode;
  late final FocusNode _repsFocusNode;
  final _weightFieldKey = GlobalKey();
  final _repsFieldKey = GlobalKey();
  final _rpeFieldKey = GlobalKey();

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
    _fallbackWeightFocusNode = FocusNode();
    _repsFocusNode = FocusNode();
    _weightFocusNode.addListener(_scrollWeightIntoViewOnFocus);
    _repsFocusNode.addListener(_scrollRepsIntoViewOnFocus);
  }

  @override
  void didUpdateWidget(covariant _SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weightFocusNode != widget.weightFocusNode) {
      oldWidget.weightFocusNode?.removeListener(_scrollWeightIntoViewOnFocus);
      _fallbackWeightFocusNode.removeListener(_scrollWeightIntoViewOnFocus);
      _weightFocusNode.addListener(_scrollWeightIntoViewOnFocus);
    }
    // Resync if upstream value diverged (e.g. duplicated from prev set).
    if (oldWidget.set.weightKg != widget.set.weightKg) {
      _weight.text = _fmtWeight(widget.set.weightKg);
    }
    if (oldWidget.set.reps != widget.set.reps) {
      _reps.text = widget.set.reps == 0 ? '' : widget.set.reps.toString();
    }
    if (oldWidget.set.rpeX10 != widget.set.rpeX10) {
      _rpe.text = widget.set.rpeX10 == null
          ? ''
          : (widget.set.rpeX10! / 10).toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _weightFocusNode.removeListener(_scrollWeightIntoViewOnFocus);
    _repsFocusNode.removeListener(_scrollRepsIntoViewOnFocus);
    _fallbackWeightFocusNode.dispose();
    _repsFocusNode.dispose();
    _weight.dispose();
    _reps.dispose();
    _rpe.dispose();
    super.dispose();
  }

  FocusNode get _weightFocusNode =>
      widget.weightFocusNode ?? _fallbackWeightFocusNode;

  void _scrollWeightIntoViewOnFocus() {
    if (_weightFocusNode.hasFocus) {
      _scrollFieldIntoView(_weightFieldKey);
    }
  }

  void _scrollRepsIntoViewOnFocus() {
    if (_repsFocusNode.hasFocus) {
      _scrollFieldIntoView(_repsFieldKey);
    }
  }

  void _scrollFieldIntoView(GlobalKey fieldKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      final cardContext = widget.cardKey?.currentContext;
      final fieldContext = fieldKey.currentContext;

      if (cardContext != null && cardContext.mounted) {
        await Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
      } else if (fieldContext != null && fieldContext.mounted) {
        await Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
      }
    });
  }

  /// Sets are stored in kilograms; the field shows and accepts the user's
  /// chosen unit, so an imperial user types and reads pounds throughout.
  WeightFormat get _fmt => ref.read(weightFormatProvider);

  String _fmtWeight(double kg) => kg == 0 ? '' : _fmt.formatValue(kg);

  String get _hintWeight {
    if (widget.priorSet == null) return '';
    return _fmtWeight(widget.priorSet!.weightKg);
  }

  String get _hintReps {
    if (widget.priorSet == null) return '';
    return widget.priorSet!.reps == 0 ? '' : widget.priorSet!.reps.toString();
  }

  /// Set index cell: warmups show 'W', Down Sets show their position in the
  /// current chain ('D1', 'D2', …), other non-standard types show their
  /// badge ('D' drop, 'RP' rest-pause, …), plain sets show the number.
  String _indexLabel() {
    if (widget.set.isWarmup) return 'W';
    final type = SetType.fromId(widget.set.setType);
    if (type == SetType.downSets) return 'D${widget.downSetOrdinal}';
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
    widget.onUpdate(
      entered == null ? null : _fmt.toKg(entered),
      r,
      rpe == null ? null : (rpe * 10).round(),
      rpe == null,
    );
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
                // Long-pressing a Down Set opens the auto-fill wizard.
                InkWell(
                  onTap: widget.onTypeTap,
                  onLongPress:
                      SetType.fromId(widget.set.setType) == SetType.downSets
                      ? () async {
                          Haptics.medium();
                          final result = await DownSetConfigSheet.show(
                            context,
                            initialWeightKg: widget.set.weightKg,
                            initialReps: widget.set.reps == 0
                                ? 10
                                : widget.set.reps,
                          );
                          if (result != null) {
                            await widget.onDownSetChain(result);
                          }
                        }
                      : null,
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
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onLongPress: () {
                      Haptics.medium();
                      final kg = double.tryParse(_weight.text);
                      final weightKg = kg != null ? _fmt.toKg(kg) : null;
                      PlateCalculatorSheet.show(context, weightKg: weightKg);
                    },
                    child: _numberField(
                      _weight,
                      decimal: true,
                      fillColor: Colors.blue.withValues(alpha: 0.12),
                      focusNode: _weightFocusNode,
                      fieldKey: _weightFieldKey,
                      hintText: _hintWeight,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: _numberField(
                    _reps,
                    fillColor: Colors.orange.withValues(alpha: 0.12),
                    focusNode: _repsFocusNode,
                    fieldKey: _repsFieldKey,
                    hintText: _hintReps,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: _rpeField(context),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: Icon(
                    Icons.construction,
                    size: 16,
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
                    if (!isCompleted) {
                      if (_weight.text.trim().isEmpty && _hintWeight.isNotEmpty) {
                        _weight.text = _hintWeight;
                      }
                      if (_reps.text.trim().isEmpty && _hintReps.isNotEmpty) {
                        _reps.text = _hintReps;
                      }
                    }
                    _commit();
                    widget.onComplete(!isCompleted);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
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
                          : Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.outline,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.microLabelText != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2),
                child: Text(
                  widget.microLabelText!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
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
    GlobalKey? fieldKey,
    String? hintText,
  }) {
    final theme = Theme.of(context);
    return TextField(
      key: fieldKey,
      controller: ctrl,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onTap: fieldKey == null ? null : () => _scrollFieldIntoView(fieldKey),
      onEditingComplete: _commit,
      onSubmitted: (_) {
        _commit();
        FocusManager.instance.primaryFocus?.unfocus();
      },
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
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        filled: true,
        fillColor: fillColor ?? AppColors.surfaceVariant,
        hintText: hintText,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          fontWeight: FontWeight.normal,
        ),
        // Pill-shaped set inputs (stadium border).
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _rpeField(BuildContext context) {
    final theme = Theme.of(context);
    final val = _rpe.text.isEmpty ? null : double.tryParse(_rpe.text);
    return InkWell(
      key: _rpeFieldKey,
      onTap: () {
        _scrollFieldIntoView(_rpeFieldKey);
        _showRpeGrid(context);
      },
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
    var selected = double.tryParse(_rpe.text) ?? 8.0;
    final res = await showModalBottomSheet<double?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select RPE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      selected.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                        color: Colors.purple,
                      ),
                    ),
                    Slider(
                      value: selected,
                      min: 5.0,
                      max: 10.0,
                      divisions: 10,
                      label: selected.toStringAsFixed(1),
                      onChanged: (value) {
                        setModalState(() => selected = value);
                      },
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, -1.0),
                          child: const Text('Clear RPE'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
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

/// Per-exercise assisted-rep-tracking opt-in, shown in the exercise options
/// menu for an eligible slug (Task 1, REP-01). When consent has not been
/// granted, this degrades to a link back to the dedicated consent screen —
/// **never** a silent no-op and never an inline consent shortcut.
class _RepTrackingMenuTile extends ConsumerWidget {
  const _RepTrackingMenuTile({required this.exerciseSlug});

  final String exerciseSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(repTrackingSettingsProvider);
    final consented = settingsAsync.asData?.value?.consentGrantedAt != null;

    if (!consented) {
      return ListTile(
        leading: const Icon(Icons.sensors_outlined),
        title: const Text('Assisted rep tracking'),
        subtitle: const Text('Enable from the consent screen first'),
        onTap: () {
          Navigator.pop(context);
          context.push('/rep-tracking-consent');
        },
      );
    }

    final enabledAsync =
        ref.watch(repTrackingEnabledForProvider(exerciseSlug));
    final enabled = enabledAsync.asData?.value ?? false;

    return ListTile(
      leading: const Icon(Icons.sensors_outlined),
      title: const Text('Assisted rep tracking'),
      subtitle: const Text('Propose a rep count for this exercise'),
      trailing: Switch(
        value: enabled,
        onChanged: (val) {
          ref
              .read(repTrackingRepositoryProvider)
              .setExerciseEnabled(exerciseSlug, val);
          ref.invalidate(repTrackingEnabledForProvider(exerciseSlug));
        },
      ),
    );
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
