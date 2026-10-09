import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/drop_set_rounding.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/set_metric_format.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/sheets/accessory_tray_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/down_set_config_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/duration_wheel_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/equipment_variant_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/machine_config_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/plate_calculator_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/progression_override_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/smart_substitution_sheet.dart';
import 'package:herculex/features/workouts/presentation/sheets/workout_settings_sheet.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';
import 'package:herculex/features/workouts/presentation/widgets/set_type_menu.dart';

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

  @override
  Widget build(BuildContext context) {
    final workoutExercise = widget.workoutExercise;
    final exercise = widget.exercise;
    final theme = Theme.of(context);
    final sets = ref.watch(setsForWorkoutExerciseProvider(workoutExercise.id));
    final lastPerformance = ref.watch(lastPerformanceProvider(exercise.id));
    final repo = ref.watch(workoutsRepositoryProvider);
    final weightFmt = ref.watch(weightFormatProvider);
    final distanceFmt = ref.watch(distanceFormatProvider);
    final hintMode = ref.watch(performanceHintModeProvider);
    // What this exercise is measured in. Everything the card renders for a set
    // — the column headers, the inputs, the last-time hint — is derived from
    // this one value (EXR-05).
    final variant = workoutExercise.equipmentVariant ?? exercise.modality;
    final metric = effectiveLoggingMetric(
      exercise: exercise,
      equipmentVariant: workoutExercise.equipmentVariant,
    );
    final isWeightedBw =
        variant == 'weighted' ||
        (exercise.supportsWeightedBodyweight && variant == 'weighted');
    final isBodyweight = variant == 'bodyweight' || variant == 'band';
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Haptics.selection();
                    context.push(AppPaths.exercise(exercise.id));
                  },
                  child: Row(
                    children: [
                      ExerciseArtwork(
                        exercise: exercise,
                        size: 32,
                        radius: 16,
                        equipmentVariant: workoutExercise.equipmentVariant,
                      ),
                      const SizedBox(width: 12),
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
                          ],
                        ),
                      ),
                    ],
                  ),
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
              final isNextMode = hintMode == PerformanceHintMode.next;

              if (isNextMode) {
                final nextTarget = _formatNextTarget(
                  ref,
                  currentRows,
                  allLastSets,
                  weightFmt,
                  metric,
                );
                if (nextTarget == null || nextTarget.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                final nextLabel = _nextLabel(snapshot, currentRows);
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: nextTarget.rationale ?? '',
                          child: Text(
                            '$nextLabel: ${nextTarget.text}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (currentRows.any(
                        (row) => !row.isCompleted && !row.isWarmup,
                      ))
                        TextButton(
                          onPressed: () => _applyNumericTarget(
                            context,
                            repo,
                            currentRows,
                            weightKg: nextTarget.weightKg,
                            reps: nextTarget.reps,
                            rationale: nextTarget.rationale,
                          ),
                          child: const Text('Use'),
                        ),
                    ],
                  ),
                );
              }

              final lastText = _formatLast(
                currentRows,
                allLastSets,
                weightFmt,
                distanceFmt,
                metric,
              );
              if (lastText.isEmpty) {
                return const SizedBox.shrink();
              }

              final lastLabel = _lastLabel(snapshot, currentRows);
              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '$lastLabel: $lastText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          _HeaderRow(
            theme: theme,
            metric: metric,
            isWeightedBodyweight: isWeightedBw,
          ),
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
              // Working sets count from 1 past any warmups (W W 1 2 3).
              final setNumbers = numberSets(rows);
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
                      index: setNumbers[i].ordinal,
                      set: rows[i],
                      metric: metric,
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
                        distanceFmt,
                        metric,
                      ),
                      weightFocusNode: i == 0 ? widget.firstSetFocusNode : null,
                      cardKey: _cardKey,
                      onUpdate: (values) => repo.updateSet(
                        setId: rows[i].id,
                        weightKg: values.weightKg,
                        reps: values.reps,
                        durationSeconds: values.durationSeconds,
                        distanceM: values.distanceM,
                        calories: values.calories,
                        rpeX10: values.rpeX10,
                        clearRpe: values.clearRpe,
                      ),
                      onComplete: (completed) async {
                        // The rest timer starts itself from the database
                        // change (restTimerAutoStartProvider), so it no
                        // longer depends on anything below succeeding.
                        await repo.updateSet(
                          setId: rows[i].id,
                          isCompleted: completed,
                        );
                        if (completed) {
                          if (!rows[i].isWarmup) {
                            final attachedIds =
                                ref
                                    .read(setAccessoriesProvider(rows[i].id))
                                    .asData
                                    ?.value
                                    .map((a) => a.accessoryId)
                                    .toSet() ??
                                const <int>{};
                            final allAcc =
                                ref.read(accessoriesProvider).asData?.value ??
                                const [];
                            final accNames = allAcc
                                .where((a) => attachedIds.contains(a.id))
                                .map((a) => a.name)
                                .toList();
                            final effectiveKg =
                                rows[i].weightKg +
                                (rows[i].bodyweightKg ?? 0.0) +
                                (rows[i].chainsKg ?? 0.0);
                            ref
                                .read(gamificationServiceProvider)
                                .onSetCompleted(
                                  sessionId: workoutExercise.sessionId,
                                  exerciseId: exercise.id,
                                  exerciseName: exercise.name,
                                  primaryMuscle: exercise.primaryMuscle,
                                  effectiveKg: effectiveKg,
                                  weightKg: rows[i].weightKg,
                                  reps: rows[i].reps,
                                  accessoryNames: accNames,
                                  equipmentVariant:
                                      workoutExercise.equipmentVariant ??
                                      exercise.modality,
                                  setType: SetType.fromId(rows[i].setType),
                                );
                          }
                          if (workoutExercise.supersetGroup != null) {
                            widget.onCompletedSet?.call(
                              workoutExercise.id,
                              rows[i].setIndex,
                            );
                          }
                        }
                      },
                      onDelete: () async {
                        final setToRestore = rows[i];
                        final setNumber = setNumbers[i].short;
                        final bands = await repo.bandsForSet(setToRestore.id);
                        final accessories = await repo.accessoriesForSet(
                          setToRestore.id,
                        );
                        await repo.deleteSet(setToRestore.id);
                        if (context.mounted) {
                          ref
                              .read(
                                inAppNotificationControllerProvider.notifier,
                              )
                              .show(
                                InAppNotificationItem.workoutAction(
                                  label:
                                      '${widget.exercise.name} · Set deleted',
                                  value: 'Set $setNumber deleted',
                                  actionLabel: 'Undo',
                                  onAction: () async {
                                    await repo.restoreSet(
                                      setToRestore,
                                      bands: bands,
                                      accessories: accessories,
                                    );
                                  },
                                ),
                              );
                        }
                      },
                      // One-tap set-type switch (§15, §26).
                      onTypeTap: () async {
                        final sel = await SetTypeMenu.show(
                          context,
                          current: SetType.fromId(rows[i].setType),
                          isWarmup: rows[i].isWarmup,
                          allowAdvancedTechniques: true,
                        );
                        if (sel != null) {
                          if (sel.delete) {
                            final setToRestore = rows[i];
                            final setNumber = setNumbers[i].short;
                            final bands = await repo.bandsForSet(
                              setToRestore.id,
                            );
                            final accessories = await repo.accessoriesForSet(
                              setToRestore.id,
                            );
                            await repo.deleteSet(setToRestore.id);
                            if (context.mounted) {
                              ref
                                  .read(
                                    inAppNotificationControllerProvider
                                        .notifier,
                                  )
                                  .show(
                                    InAppNotificationItem.workoutAction(
                                      label:
                                          '${widget.exercise.name} · Set deleted',
                                      value: 'Set $setNumber deleted',
                                      actionLabel: 'Undo',
                                      onAction: () async {
                                        await repo.restoreSet(
                                          setToRestore,
                                          bands: bands,
                                          accessories: accessories,
                                        );
                                      },
                                    ),
                                  );
                            }
                          } else if (sel.isWarmup == true) {
                            await repo.updateSet(
                              setId: rows[i].id,
                              isWarmup: true,
                              setType: SetType.standard.id,
                              clearSetTypeMetaJson: true,
                            );
                          } else {
                            await repo.updateSet(
                              setId: rows[i].id,
                              isWarmup: false,
                              setType: sel.type.id,
                              setTypeMetaJson: sel.metaJson,
                              clearSetTypeMetaJson: sel.metaJson == null,
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
                          _setsExpanded
                              ? 'Show less'
                              : 'Show all (${rows.length})',
                        ),
                      ),
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
                          workoutExercise.equipmentVariant ?? exercise.modality,
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
                  if ((exercise.supportsWeightedBodyweight || isWeightedBw) &&
                      bodyweight == null) {
                    bodyweight = await ref
                        .read(measurementsRepositoryProvider)
                        .latestBodyweightKg();
                  }
                  // Non-rep fields carry forward the same way weight and reps
                  // do — a second sled push starts at the first one's load and
                  // distance. They stay null when the metric does not use them,
                  // so an ordinary set never gains a stray zero duration.
                  final seed = prev ?? priorFirst;
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
                    durationSeconds: metric.has(SetField.duration)
                        ? seed?.durationSeconds
                        : null,
                    distanceM: metric.has(SetField.distance)
                        ? seed?.distanceM
                        : null,
                    calories: metric.has(SetField.calories)
                        ? seed?.calories
                        : null,
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
  ({
    ProgressionGoal goal,
    double? weeklyPctOverride,
    String progressionModel,
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
  })
  _progressionGoal(WidgetRef ref) {
    final override = ref
        .watch(exerciseProgressionProvider(widget.exercise.id))
        .asData
        ?.value;
    if (override != null && override.enabled) {
      final goal = ProgressionGoal.values.firstWhere(
        (g) => g.name == override.goal,
        orElse: () => ProgressionGoal.muscleGain,
      );
      return (
        goal: goal,
        weeklyPctOverride: override.weeklyIncreasePct,
        progressionModel: override.progressionModel,
        targetSets: override.targetSets,
        targetRepsMin: override.targetRepsMin,
        targetRepsMax: override.targetRepsMax,
      );
    }
    final fitnessGoal =
        ref.watch(effectiveFitnessGoalProvider) ?? FitnessGoal.maintenance;
    final goal = switch (fitnessGoal) {
      FitnessGoal.weightLoss => ProgressionGoal.fatLoss,
      FitnessGoal.muscleGain ||
      FitnessGoal.maintenance => ProgressionGoal.muscleGain,
      FitnessGoal.improveHealth => ProgressionGoal.endurance,
    };
    return (
      goal: goal,
      weeklyPctOverride: null,
      progressionModel: 'linear',
      targetSets: null,
      targetRepsMin: null,
      targetRepsMax: null,
    );
  }

  String _nextLabel(
    LastPerformanceSnapshot? snapshot,
    List<SetEntryData> currentRows,
  ) {
    String setSpec = '';
    if (currentRows.isNotEmpty) {
      var activeIndex = currentRows.indexWhere((r) => !r.isCompleted);
      if (activeIndex == -1) {
        activeIndex = currentRows.length - 1;
      }
      if (activeIndex >= 0 && activeIndex < currentRows.length) {
        final activeSet = currentRows[activeIndex];
        if (activeSet.isWarmup) {
          final warmups = currentRows.where((s) => s.isWarmup).toList();
          final wIdx = warmups.indexOf(activeSet) + 1;
          setSpec = warmups.length > 1 ? 'W$wIdx' : 'W';
        } else if (activeSet.setType == 'down_sets') {
          var count = 0;
          for (var k = 0; k <= activeIndex; k++) {
            if (currentRows[k].setType == 'down_sets') {
              count++;
            } else {
              count = 0;
            }
          }
          setSpec = 'D$count';
        } else if (activeSet.setType == 'standard') {
          setSpec = '${_ordinal(activeIndex + 1)} set';
        } else {
          final type = SetType.fromId(activeSet.setType);
          setSpec = type.label;
        }
      }
    }

    final currentVariant =
        widget.workoutExercise.equipmentVariant ?? widget.exercise.modality;
    final priorVariant = snapshot?.equipmentVariant;
    final hasDifferentVariant =
        priorVariant != null &&
        priorVariant.isNotEmpty &&
        priorVariant != currentVariant;

    if (hasDifferentVariant) {
      final variantLabel = EquipmentVariantSheet.labelFor(priorVariant);
      if (setSpec.isNotEmpty) {
        return 'Next on $variantLabel ($setSpec)';
      }
      return 'Next on $variantLabel';
    }

    if (setSpec.isNotEmpty) {
      return 'Next $setSpec';
    }
    return 'Next';
  }

  ({String text, String? rationale, double weightKg, int reps})?
  _formatNextTarget(
    WidgetRef ref,
    List<SetEntryData> currentRows,
    List<SetEntryData> allLastSets,
    WeightFormat fmt,
    LoggingMetric metric,
  ) {
    if (allLastSets.isEmpty) return null;
    if (!metric.isRepBased) return null;
    if (widget.workoutExercise.plannedTrainingMethod == 'max_effort' ||
        widget.workoutExercise.plannedTrainingMethod == 'dynamic_effort') {
      return null;
    }

    SetEntryData? prior;
    if (currentRows.isEmpty) {
      prior =
          allLastSets.where((s) => !s.isWarmup).firstOrNull ??
          allLastSets.firstOrNull;
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

    if (prior == null || prior.isWarmup) return null;

    final settings = _progressionGoal(ref);
    final allPastSets = allLastSets
        .where((s) => !s.isWarmup)
        .map((s) => (weightKg: s.weightKg, reps: s.reps))
        .toList();

    final target = ProgressionEngine.suggestNext(
      lastWeightKg: prior.weightKg,
      lastReps: prior.reps,
      goal: settings.goal,
      equipmentVariant:
          widget.workoutExercise.equipmentVariant ?? widget.exercise.modality,
      weeklyIncreasePctOverride: settings.weeklyPctOverride,
      allLastSets: allPastSets,
      progressionModel: settings.progressionModel,
      targetSets: settings.targetSets,
      targetRepsMin: settings.targetRepsMin,
      targetRepsMax: settings.targetRepsMax,
    );

    if (target.weightKg <= 0 && prior.weightKg <= 0) return null;
    final isWeightedBw =
        (widget.workoutExercise.equipmentVariant ?? widget.exercise.modality) ==
        'weighted';
    final nextPrefix = isWeightedBw && target.weightKg > 0 ? '+' : '';
    final text = '$nextPrefix${fmt.format(target.weightKg)} × ${target.reps}';
    return (
      text: text,
      rationale: target.rationale,
      weightKg: target.weightKg,
      reps: target.reps,
    );
  }

  Future<void> _applyNumericTarget(
    BuildContext context,
    WorkoutsRepository repo,
    List<SetEntryData> rows, {
    required double weightKg,
    required int reps,
    String? rationale,
  }) async {
    final targets = rows
        .where((row) => !row.isCompleted && !row.isWarmup)
        .toList(growable: false);
    if (targets.isEmpty) return;
    final before = [
      for (final row in targets)
        (id: row.id, weightKg: row.weightKg, reps: row.reps),
    ];
    for (final row in targets) {
      await repo.updateSet(setId: row.id, weightKg: weightKg, reps: reps);
    }
    if (!context.mounted) return;
    ref
        .read(inAppNotificationControllerProvider.notifier)
        .show(
          InAppNotificationItem.workoutAction(
            label: widget.exercise.name,
            value: rationale == null || rationale.trim().isEmpty
                ? 'Safe numeric target applied'
                : 'Target applied: $rationale',
            actionLabel: 'Undo',
            onAction: () async {
              for (final row in before) {
                await repo.updateSet(
                  setId: row.id,
                  weightKg: row.weightKg,
                  reps: row.reps,
                );
              }
            },
          ),
        );
  }

  /// Per-row micro-label under a set (item 1): a compact "Down: X-Y" once per
  /// down-set chain.
  String? _microLabelFor(
    WidgetRef ref,
    List<SetEntryData> rows,
    List<SetEntryData> allLastSets,
    List<int> downSetOrdinals,
    int i,
    PerformanceHintMode hintMode,
    WeightFormat weightFmt,
    DistanceFormat distanceFmt,
    LoggingMetric metric,
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
    // No per-row hints (only top hint is shown for both Last and Next).
    return null;
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) {
      return '${n}th';
    }
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  String _lastLabel(
    LastPerformanceSnapshot? snapshot,
    List<SetEntryData> currentRows,
  ) {
    String setSpec = '';
    if (currentRows.isNotEmpty) {
      var activeIndex = currentRows.indexWhere((r) => !r.isCompleted);
      if (activeIndex == -1) {
        activeIndex = currentRows.length - 1;
      }
      if (activeIndex >= 0 && activeIndex < currentRows.length) {
        final activeSet = currentRows[activeIndex];
        if (activeSet.isWarmup) {
          final warmups = currentRows.where((s) => s.isWarmup).toList();
          final wIdx = warmups.indexOf(activeSet) + 1;
          setSpec = warmups.length > 1 ? 'W$wIdx' : 'W';
        } else if (activeSet.setType == 'down_sets') {
          var count = 0;
          for (var k = 0; k <= activeIndex; k++) {
            if (currentRows[k].setType == 'down_sets') {
              count++;
            } else {
              count = 0;
            }
          }
          setSpec = 'D$count';
        } else if (activeSet.setType == 'standard') {
          setSpec = '${_ordinal(activeIndex + 1)} set';
        } else {
          final type = SetType.fromId(activeSet.setType);
          setSpec = type.label;
        }
      }
    }

    final currentVariant =
        widget.workoutExercise.equipmentVariant ?? widget.exercise.modality;
    final priorVariant = snapshot?.equipmentVariant;
    final hasDifferentVariant =
        priorVariant != null &&
        priorVariant.isNotEmpty &&
        priorVariant != currentVariant;

    if (hasDifferentVariant) {
      final variantLabel = EquipmentVariantSheet.labelFor(priorVariant);
      if (setSpec.isNotEmpty) {
        return 'Last on $variantLabel ($setSpec)';
      }
      return 'Last on $variantLabel';
    }

    if (setSpec.isNotEmpty) {
      return 'Last $setSpec';
    }
    return 'Last';
  }

  String _formatLast(
    List<SetEntryData> currentRows,
    List<SetEntryData> allLastSets,
    WeightFormat fmt,
    DistanceFormat distanceFmt,
    LoggingMetric metric,
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
    final isWeightedBw =
        (widget.workoutExercise.equipmentVariant ?? widget.exercise.modality) ==
        'weighted';
    final summary = SetMetricFormat.summariseSet(
      prior,
      metric: metric,
      weight: fmt,
      distance: distanceFmt,
      isWeightedBodyweight: isWeightedBw,
    );
    return '$summary$rpe';
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final isMachine =
        (widget.workoutExercise.equipmentVariant ?? widget.exercise.modality)
            .startsWith('machine');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
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
                title: const Text('Exercise info'),
                subtitle: const Text('View full exercise details & analytics'),
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppPaths.exercise(widget.exercise.id));
                },
              ),
              if (widget.workoutExercise.plannedPrescriptionWhy != null &&
                  widget.workoutExercise.plannedPrescriptionWhy!
                      .trim()
                      .isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Prescription target'),
                  subtitle: Text(
                    widget.workoutExercise.plannedPrescriptionWhy!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Prescription target'),
                        content: Text(
                          widget.workoutExercise.plannedPrescriptionWhy!,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Got it'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.fitness_center),
                title: const Text('Change equipment'),
                subtitle: Text(
                  EquipmentVariantSheet.labelFor(
                    widget.workoutExercise.equipmentVariant ??
                        widget.exercise.modality,
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
                subtitle: const Text(
                  'Override rep range & weekly load increase',
                ),
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
        widget.sessionExercises
            .where((we) => we.id != widget.workoutExercise.id)
            .toList()
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
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
      ),
    );
  }

  String _exerciseName(int exerciseId) {
    return widget.catalogExercises
            .firstWhereOrNull((e) => e.id == exerciseId)
            ?.name ??
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

  /// What this exercise is measured in. The header labels exactly the columns
  /// [_SetRow] renders, both derived from `metric.fields` so they cannot
  /// disagree (EXR-05).
  final LoggingMetric metric;
  final bool isWeightedBodyweight;

  const _HeaderRow({
    required this.theme,
    required this.metric,
    this.isWeightedBodyweight = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.secondary,
      letterSpacing: 0.8,
    );
    // Weight and distance columns are labelled with whatever unit the fields
    // expect; reps, time and calories are unit-system independent.
    final weightFmt = ref.watch(weightFormatProvider);
    final distanceFmt = ref.watch(distanceFormatProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(child: Text('SET', style: s)),
          ),
          for (final field in metric.fields) ...[
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Text(
                field == SetField.weight && isWeightedBodyweight
                    ? '+${weightFmt.suffix.toUpperCase()}'
                    : SetMetricFormat.fieldLabel(
                        field,
                        weight: weightFmt,
                        distance: distanceFmt,
                      ),
                style: s,
                textAlign: TextAlign.center,
              ),
            ),
          ],
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

/// Everything one set row can hold, in the units the repository stores.
///
/// A field is null when the exercise's [LoggingMetric] does not declare it, or
/// when the user has not typed anything into it yet — the row never invents a
/// zero for a measurement that was not taken (EXR-05).
class SetFieldValues {
  final double? weightKg;
  final int? reps;
  final int? durationSeconds;
  final double? distanceM;
  final int? calories;
  final int? rpeX10;
  final bool clearRpe;

  const SetFieldValues({
    this.weightKg,
    this.reps,
    this.durationSeconds,
    this.distanceM,
    this.calories,
    this.rpeX10,
    this.clearRpe = false,
  });
}

class _SetRow extends ConsumerStatefulWidget {
  final int index;
  final SetEntryData set;

  /// What this exercise is measured in — decides which inputs exist at all.
  final LoggingMetric metric;
  final int downSetOrdinal;
  final SetEntryData? priorSet;
  final String? microLabelText;
  final FocusNode? weightFocusNode;
  final GlobalKey? cardKey;
  final Future<void> Function(SetFieldValues values) onUpdate;
  final Future<void> Function(bool completed) onComplete;
  final VoidCallback onDelete;
  final VoidCallback onTypeTap;
  final Future<void> Function(DownSetChainResult result) onDownSetChain;
  final VoidCallback onAccessories;

  const _SetRow({
    required this.index,
    required this.set,
    required this.metric,
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
  late final TextEditingController _duration;
  late final TextEditingController _distance;
  late final TextEditingController _calories;
  late final TextEditingController _rpe;
  late final FocusNode _fallbackWeightFocusNode;
  late final FocusNode _repsFocusNode;
  final _weightFieldKey = GlobalKey();
  final _repsFieldKey = GlobalKey();
  final _durationFieldKey = GlobalKey();
  final _distanceFieldKey = GlobalKey();
  final _caloriesFieldKey = GlobalKey();
  final _rpeFieldKey = GlobalKey();

  /// Saves typed values shortly after the user stops typing, so a value is
  /// never lost because the keyboard was dismissed some way other than
  /// "done" or a tap outside (back gesture, app switch, the field scrolling
  /// away) — and so the watch sees the edit without waiting for a blur.
  Timer? _commitDebounce;

  /// Set the moment the user types in the reps field. A detected count never
  /// overwrites a number the user entered themselves — a proposal that
  /// silently replaced typing would be worse than no proposal at all.

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(text: _fmtWeight(widget.set.weightKg));
    _reps = TextEditingController(
      text: widget.set.reps == 0 ? '' : widget.set.reps.toString(),
    );
    _duration = TextEditingController(
      text: SetMetricFormat.durationFieldText(widget.set.durationSeconds),
    );
    _distance = TextEditingController(text: _fmtDistance(widget.set.distanceM));
    _calories = TextEditingController(
      text: widget.set.calories == null ? '' : widget.set.calories.toString(),
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
    // A field with focus is the user's: a debounced save of their own
    // half-typed value echoing back from the database must not overwrite
    // what they have typed since.
    if (oldWidget.set.weightKg != widget.set.weightKg &&
        !_weightFocusNode.hasFocus) {
      _weight.text = _fmtWeight(widget.set.weightKg);
    }
    if (oldWidget.set.reps != widget.set.reps && !_repsFocusNode.hasFocus) {
      _reps.text = widget.set.reps == 0 ? '' : widget.set.reps.toString();
    }
    if (oldWidget.set.durationSeconds != widget.set.durationSeconds) {
      _duration.text = SetMetricFormat.durationFieldText(
        widget.set.durationSeconds,
      );
    }
    if (oldWidget.set.distanceM != widget.set.distanceM) {
      _distance.text = _fmtDistance(widget.set.distanceM);
    }
    if (oldWidget.set.calories != widget.set.calories) {
      _calories.text = widget.set.calories == null
          ? ''
          : widget.set.calories.toString();
    }
    if (oldWidget.set.rpeX10 != widget.set.rpeX10) {
      _rpe.text = widget.set.rpeX10 == null
          ? ''
          : (widget.set.rpeX10! / 10).toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    if (_weightFocusNode.hasFocus || _repsFocusNode.hasFocus) {
      // Deferred for the same reason as ActiveWorkoutView.deactivate: the
      // shell watches this flag and the tree is locked during disposal.
      final focused = ref.read(workoutInputFocusedProvider.notifier);
      Future.microtask(() => focused.state = false);
    }
    _weightFocusNode.removeListener(_scrollWeightIntoViewOnFocus);
    _repsFocusNode.removeListener(_scrollRepsIntoViewOnFocus);
    _fallbackWeightFocusNode.dispose();
    _repsFocusNode.dispose();
    _weight.dispose();
    _reps.dispose();
    _duration.dispose();
    _distance.dispose();
    _calories.dispose();
    _rpe.dispose();
    super.dispose();
  }

  FocusNode get _weightFocusNode =>
      widget.weightFocusNode ?? _fallbackWeightFocusNode;

  void _syncInputFocus() {
    if (_weightFocusNode.hasFocus || _repsFocusNode.hasFocus) {
      ref.read(workoutInputFocusedProvider.notifier).state = true;
    } else {
      ref.read(workoutInputFocusedProvider.notifier).state = false;
    }
  }

  void _scrollWeightIntoViewOnFocus() {
    _syncInputFocus();
    if (_weightFocusNode.hasFocus) {
      _scrollFieldIntoView(_weightFieldKey);
    } else {
      _commit();
    }
  }

  void _scrollRepsIntoViewOnFocus() {
    _syncInputFocus();
    if (_repsFocusNode.hasFocus) {
      _scrollFieldIntoView(_repsFieldKey);
    } else {
      _commit();
    }
  }

  void _scheduleCommit() {
    _commitDebounce?.cancel();
    _commitDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _commit();
    });
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

  /// Distances are stored in metres and typed in the user's own unit, exactly
  /// as weights are stored in kilograms and typed in kilograms or pounds.
  DistanceFormat get _distFmt => ref.read(distanceFormatProvider);

  String _fmtWeight(double kg) => kg == 0 ? '' : _fmt.formatValue(kg);

  String _fmtDistance(double? metres) =>
      metres == null || metres == 0 ? '' : _distFmt.formatValue(metres);

  /// The controller behind one declared field.
  TextEditingController _controllerFor(SetField field) => switch (field) {
    SetField.weight => _weight,
    SetField.reps => _reps,
    SetField.duration => _duration,
    SetField.distance => _distance,
    SetField.calories => _calories,
  };

  /// The previous set's value for one field, shown as a ghost hint and copied
  /// in when the user completes a set without typing anything.
  String _hintFor(SetField field) {
    final prior = widget.priorSet;
    return switch (field) {
      SetField.weight =>
        widget.set.plannedWeightKg != null
            ? _fmtWeight(widget.set.plannedWeightKg!)
            : prior == null
            ? ''
            : _fmtWeight(prior.weightKg),
      SetField.reps =>
        widget.set.plannedRepsMin != null
            ? widget.set.plannedRepsMin.toString()
            : prior == null || prior.reps == 0
            ? ''
            : prior.reps.toString(),
      SetField.duration => SetMetricFormat.durationFieldText(
        prior?.durationSeconds,
      ),
      SetField.distance => _fmtDistance(prior?.distanceM),
      SetField.calories =>
        prior?.calories == null ? '' : prior!.calories.toString(),
    };
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
    _commitDebounce?.cancel();
    _commitDebounce = null;
    final metric = widget.metric;
    final rpe = double.tryParse(_rpe.text);
    // Only the fields this exercise actually declares are sent. A field the
    // metric does not have stays null, which `updateSet` reads as "leave the
    // stored value alone" — a Plank never overwrites a weight, and switching
    // an exercise's metric never silently blanks what was already logged.
    // Typed display values are converted back to metric first; storage is
    // always kilograms and metres.
    final enteredWeight = metric.has(SetField.weight)
        ? double.tryParse(_weight.text)
        : null;
    final enteredDistance = metric.has(SetField.distance)
        ? double.tryParse(_distance.text)
        : null;
    widget.onUpdate(
      SetFieldValues(
        weightKg: enteredWeight == null ? null : _fmt.toKg(enteredWeight),
        reps: metric.has(SetField.reps) ? int.tryParse(_reps.text) : null,
        durationSeconds: metric.has(SetField.duration)
            ? SetMetricFormat.parseDuration(_duration.text)
            : null,
        distanceM: enteredDistance == null
            ? null
            : _distFmt.toM(enteredDistance),
        calories: metric.has(SetField.calories)
            ? int.tryParse(_calories.text)
            : null,
        rpeX10: rpe == null ? null : (rpe * 10).round(),
        clearRpe: rpe == null,
      ),
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

    final totalAccCount =
        attachedAccs.length +
        attachedBands.length +
        (widget.set.chainsKg != null && widget.set.chainsKg! > 0 ? 1 : 0);

    String? accBadgeText;
    if (totalAccCount >= 2) {
      accBadgeText = '$totalAccCount';
    } else if (totalAccCount == 1) {
      if (widget.set.chainsKg != null && widget.set.chainsKg! > 0) {
        accBadgeText = 'C';
      } else if (attachedBands.isNotEmpty) {
        final sb = attachedBands.first;
        accBadgeText = sb.mode == 'assistance' ? 'A' : 'B';
      } else if (attachedAccs.isNotEmpty) {
        final acc = catalogAccs.firstWhereOrNull(
          (a) => a.id == attachedAccs.first.accessoryId,
        );
        if (acc != null) {
          final nameLower = acc.name.toLowerCase();
          if (nameLower.contains('belt')) {
            accBadgeText = 'B';
          } else if (nameLower.contains('strap')) {
            accBadgeText = 'S';
          } else if (nameLower.contains('wrist')) {
            accBadgeText = 'W';
          } else if (nameLower.contains('knee')) {
            accBadgeText = 'K';
          } else if (nameLower.contains('elbow')) {
            accBadgeText = 'E';
          } else if (nameLower.contains('grip') || nameLower.contains('fat')) {
            accBadgeText = 'G';
          } else if (nameLower.contains('chalk')) {
            accBadgeText = 'C';
          } else if (nameLower.contains('shoe')) {
            accBadgeText = 'S';
          } else if (acc.name.trim().isNotEmpty) {
            accBadgeText = acc.name.trim()[0].toUpperCase();
          } else {
            accBadgeText = '1';
          }
        } else {
          accBadgeText = '1';
        }
      }
    }

    return HxStickyDismissible(
      key: ValueKey('set_${widget.set.id}'),
      borderRadius: BorderRadius.circular(8),
      onDismissed: () => widget.onDelete(),
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
                // One input per field the exercise's metric declares, in the
                // metric's own order — weight × reps for a squat, a lone
                // duration for a plank, weight and metres for a sled push.
                for (final field in widget.metric.fields) ...[
                  const SizedBox(width: 4),
                  Expanded(flex: 2, child: _fieldInput(field)),
                ],
                const SizedBox(width: 4),
                Expanded(flex: 2, child: _rpeField(context)),
                InkWell(
                  onTap: widget.onAccessories,
                  borderRadius: BorderRadius.circular(6),
                  child: Tooltip(
                    message: activeTags.isNotEmpty
                        ? 'Accessories: ${activeTags.join(", ")}'
                        : 'Accessories',
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: accBadgeText != null
                            ? Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer.withValues(
                                    alpha: 0.8,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 1.2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  accBadgeText,
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: AppColors.outline,
                              ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Haptics.medium();
                    // Completing a set the user did not fill in adopts the
                    // previous set's numbers — for every field the metric
                    // declares, not just weight and reps.
                    if (!isCompleted) {
                      for (final field in widget.metric.fields) {
                        final ctrl = _controllerFor(field);
                        final hint = _hintFor(field);
                        if (ctrl.text.trim().isEmpty && hint.isNotEmpty) {
                          ctrl.text = hint;
                        }
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
                padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
                child: Text(
                  widget.microLabelText!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
            if (SetType.fromId(widget.set.setType) == SetType.myoReps ||
                SetType.fromId(widget.set.setType) == SetType.forced ||
                SetType.fromId(widget.set.setType) == SetType.cheat)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2, bottom: 4),
                child: Builder(
                  builder: (context) {
                    final setType = SetType.fromId(widget.set.setType);
                    final meta = widget.set.setTypeMetaJson != null
                        ? jsonDecode(widget.set.setTypeMetaJson!)
                        : <String, dynamic>{};
                    final List<int> extraItems;
                    final String metaKey;
                    final String buttonLabel;
                    final String chipSuffix;
                    final Color accentColor;

                    if (setType == SetType.myoReps) {
                      metaKey = 'miniSets';
                      buttonLabel = 'Mini Set';
                      chipSuffix = 'reps';
                      accentColor = AppColors.primary;
                      extraItems =
                          (meta['miniSets'] as List<dynamic>?)?.cast<int>() ??
                          [];
                    } else if (setType == SetType.forced) {
                      metaKey = 'extraReps';
                      buttonLabel = 'Forced';
                      chipSuffix = 'forced';
                      accentColor = const Color(0xFFE53935);
                      final raw = meta['extraReps'] ?? meta['forcedReps'];
                      extraItems = raw is List
                          ? raw.cast<int>()
                          : (raw is num ? [raw.toInt()] : []);
                    } else {
                      // cheat
                      metaKey = 'extraReps';
                      buttonLabel = 'Cheat';
                      chipSuffix = 'cheat';
                      accentColor = const Color(0xFFFF7043);
                      final raw = meta['extraReps'] ?? meta['cheatReps'];
                      extraItems = raw is List
                          ? raw.cast<int>()
                          : (raw is num ? [raw.toInt()] : []);
                    }

                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int i = 0; i < extraItems.length; i++)
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Remove $chipSuffix?'),
                                  content: Text(
                                    'Do you want to remove +${extraItems[i]} $chipSuffix?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final newItems = List<int>.from(extraItems)
                                  ..removeAt(i);
                                meta[metaKey] = newItems;
                                await ref
                                    .read(workoutsRepositoryProvider)
                                    .updateSet(
                                      setId: widget.set.id,
                                      setTypeMetaJson: jsonEncode(meta),
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
                                color: accentColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    setType == SetType.myoReps
                                        ? '${extraItems[i]} $chipSuffix'
                                        : '+${extraItems[i]} $chipSuffix',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
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
                              hint: 'No. of extra reps (e.g. 2)',
                            );
                            if (reps != null && reps > 0) {
                              final newItems = List<int>.from(extraItems)
                                ..add(reps);
                              meta[metaKey] = newItems;
                              await ref
                                  .read(workoutsRepositoryProvider)
                                  .updateSet(
                                    setId: widget.set.id,
                                    setTypeMetaJson: jsonEncode(meta),
                                  );
                              if (setType == SetType.myoReps) {
                                ref
                                    .read(restTimerProvider.notifier)
                                    .start(
                                      seconds: 15,
                                      exerciseName: 'Myo-rep Rest',
                                    );
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
                              color: accentColor.withValues(alpha: 0.1),
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
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

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

  /// One declared input, with the affordances that belong to that field only:
  /// the plate calculator hangs off weight, the rep-tracker edit flag off reps,
  /// and duration accepts `m:ss` as well as a bare seconds count.
  Widget _fieldInput(SetField field) {
    switch (field) {
      case SetField.weight:
        return GestureDetector(
          onLongPress: () {
            Haptics.medium();
            final entered = double.tryParse(_weight.text);
            final weightKg = entered != null ? _fmt.toKg(entered) : null;
            PlateCalculatorSheet.show(context, weightKg: weightKg);
          },
          child: _numberField(
            _weight,
            decimal: true,
            fillColor: Colors.blue.withValues(alpha: 0.12),
            focusNode: _weightFocusNode,
            fieldKey: _weightFieldKey,
            hintText: _hintFor(field),
          ),
        );
      case SetField.reps:
        return _numberField(
          _reps,
          fillColor: Colors.orange.withValues(alpha: 0.12),
          focusNode: _repsFocusNode,
          fieldKey: _repsFieldKey,
          hintText: _hintFor(field),
        );
      case SetField.duration:
        final currentSec =
            SetMetricFormat.parseDuration(_duration.text) ??
            SetMetricFormat.parseDuration(_hintFor(field)) ??
            30;
        return GestureDetector(
          onTap: () async {
            Haptics.medium();
            final selected = await DurationWheelSheet.show(
              context,
              initialSeconds: currentSec,
            );
            if (selected != null) {
              _duration.text = SetMetricFormat.durationFieldText(selected);
              _commit();
            }
          },
          child: AbsorbPointer(
            child: _numberField(
              _duration,
              allowColon: true,
              fillColor: Colors.teal.withValues(alpha: 0.12),
              fieldKey: _durationFieldKey,
              hintText: _hintFor(field),
            ),
          ),
        );
      case SetField.distance:
        return _numberField(
          _distance,
          decimal: true,
          fillColor: Colors.purple.withValues(alpha: 0.12),
          fieldKey: _distanceFieldKey,
          hintText: _hintFor(field),
        );
      case SetField.calories:
        return _numberField(
          _calories,
          fillColor: Colors.red.withValues(alpha: 0.12),
          fieldKey: _caloriesFieldKey,
          hintText: _hintFor(field),
        );
    }
  }

  Widget _numberField(
    TextEditingController ctrl, {
    bool decimal = false,
    bool allowColon = false,
    Color? fillColor,
    FocusNode? focusNode,
    GlobalKey? fieldKey,
    String? hintText,
    ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    return TextField(
      key: fieldKey,
      controller: ctrl,
      focusNode: focusNode,
      onChanged: onChanged ?? (_) => _scheduleCommit(),
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
          allowColon
              ? RegExp(r'[0-9:]')
              : decimal
              ? RegExp(r'[0-9.]')
              : RegExp(r'[0-9]'),
        ),
      ],
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
          val != null
              ? val.toStringAsFixed(1)
              : widget.set.plannedRpeX10 != null
              ? '→ ${(widget.set.plannedRpeX10! / 10).toStringAsFixed(1)}'
              : 'RPE',
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
