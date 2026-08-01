import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import 'equipment_variant_sheet.dart';
import 'rest_timer_controller.dart';
import 'workouts_providers.dart';

/// Dynamic workout mode (§14): full-screen, distraction-free view with a
/// large exercise display, big timer, and big rep/set counters. One tap
/// returns to the Classic view.
class DynamicWorkoutView extends ConsumerStatefulWidget {
  final WorkoutSessionData session;
  const DynamicWorkoutView({super.key, required this.session});

  @override
  ConsumerState<DynamicWorkoutView> createState() => _DynamicWorkoutViewState();
}

class _DynamicWorkoutViewState extends ConsumerState<DynamicWorkoutView> {
  late final PageController _pageController;
  int _exerciseIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises =
        ref.watch(sessionExercisesProvider(widget.session.id)).asData?.value ??
            const <WorkoutExerciseData>[];
    final catalog =
        ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter())).asData?.value ?? const [];
    final restTimer = ref.watch(restTimerProvider);

    if (_exerciseIndex >= exercises.length && exercises.isNotEmpty) {
      _exerciseIndex = exercises.length - 1;
    }

    return SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.fullscreen_exit),
                tooltip: 'Classic mode',
                onPressed: () =>
                    ref.read(dynamicWorkoutModeProvider.notifier).state = false,
              ),
              const Spacer(),
              if (exercises.length > 1) ...[
                Text('${_exerciseIndex + 1}/${exercises.length}',
                    style: theme.textTheme.titleSmall),
                const SizedBox(width: 16),
              ],
            ],
          ),
          Expanded(
            child: exercises.isEmpty
                ? Center(
                    child: Text('Add exercises in Classic mode',
                        style: theme.textTheme.titleMedium))
                : PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _exerciseIndex = idx),
                    itemCount: exercises.length,
                    itemBuilder: (context, idx) {
                      final we = exercises[idx];
                      final exercise = catalog.firstWhereOrNull((e) => e.id == we.exerciseId);
                      final sets = ref.watch(setsForWorkoutExerciseProvider(we.id)).asData?.value ??
                          const <SetEntryData>[];
                      final nextSet = sets.firstWhereOrNull((s) => !s.isCompleted);
                      final completedCount = sets.where((s) => s.isCompleted).length;

                      if (exercise == null) return const SizedBox.shrink();

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          exercise.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displayMedium
                              ?.copyWith(fontSize: 34, height: 1.1),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        EquipmentVariantSheet.labelFor(
                            we.equipmentVariant ?? exercise.modality),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: AppColors.secondary),
                      ),
                      const SizedBox(height: 32),
                      // Big rest timer or big set counter.
                      if (restTimer.isRunning)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('REST',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2)),
                            Text(
                              _fmtSeconds(
                                  restTimer.remainingSecondsFrom(DateTime.now())),
                              style: theme.textTheme.displayLarge?.copyWith(
                                fontSize: 88,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'SET ${completedCount + (nextSet != null ? 1 : 0)}/${sets.length}',
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (nextSet != null) ...[
                        Text(
                          '${_fmtWeight(nextSet.weightKg)} kg × ${nextSet.reps}',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontSize: 44,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _DynamicSetAccessoryPills(setId: nextSet.id),
                      ] else
                        Text('All sets done 🎉',
                            style: theme.textTheme.titleLarge),
                      ],
                    );
                  },
                ),
          ),
          Builder(
            builder: (context) {
              final currentWe = exercises.elementAtOrNull(_exerciseIndex);
              final currentSets = currentWe == null
                  ? const <SetEntryData>[]
                  : ref.watch(setsForWorkoutExerciseProvider(currentWe.id)).asData?.value ??
                      const <SetEntryData>[];
              final currentNextSet = currentSets.firstWhereOrNull((s) => !s.isCompleted);
              final currentExercise = currentWe == null
                  ? null
                  : catalog.firstWhereOrNull((e) => e.id == currentWe.exerciseId);
              
              if (currentWe != null && currentNextSet != null) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 110),
                  child: SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () async {
                        final repo = ref.read(workoutsRepositoryProvider);
                        final ex = currentExercise!;
                        await repo.updateSet(setId: currentNextSet.id, isCompleted: true);
                        ref.read(restTimerProvider.notifier).start(
                              seconds:
                                  currentWe.targetRestSeconds ?? ex.defaultRestSeconds,
                              exerciseName: ex.name,
                            );
                      },
                      child: const Text('COMPLETE SET',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  String _fmtSeconds(int s) =>
      '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  String _fmtWeight(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _DynamicSetAccessoryPills extends ConsumerWidget {
  final int setId;
  const _DynamicSetAccessoryPills({required this.setId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attachedAccs = ref.watch(setAccessoriesProvider(setId)).asData?.value ?? const [];
    final attachedBands = ref.watch(setBandsProvider(setId)).asData?.value ?? const [];
    final catalogAccs = ref.watch(accessoriesProvider).asData?.value ?? const [];
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
              color: AppColors.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
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
