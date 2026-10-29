part of '../dynamic_workout_view.dart';

/// Where to go after a set of [current] is completed, given which exercises
/// still have [open] sets: the session index of the next set's exercise, and
/// the done step to show first, if any.
///
/// Supersets rotate through their exercises first. Otherwise the lifter stays
/// on [current] until it is done, then moves to the next exercise with open
/// sets (wrapping round to skipped ones). Nothing open anywhere means the
/// workout is done.
(int?, _Done?) _nextStep(
  List<WorkoutExerciseData> exercises,
  WorkoutExerciseData current,
  Map<int, bool> open,
) {
  final currentIdx = exercises.indexWhere((e) => e.id == current.id);
  final group = current.supersetGroup;
  int? nextIdx;
  if (group != null) {
    final mates = exercises.where((e) => e.supersetGroup == group).toList();
    final pos = mates.indexWhere((e) => e.id == current.id);
    for (var step = 1; step <= mates.length; step++) {
      final candidate = mates[(pos + step) % mates.length];
      if (open[candidate.id] == true) {
        nextIdx = exercises.indexOf(candidate);
        break;
      }
    }
  } else if (open[current.id] == true) {
    nextIdx = currentIdx;
  }
  if (nextIdx == null) {
    for (final i in [
      for (var i = currentIdx + 1; i < exercises.length; i++) i,
      for (var i = 0; i < currentIdx; i++) i,
    ]) {
      if (open[exercises[i].id] == true) {
        nextIdx = i;
        break;
      }
    }
  }

  if (nextIdx == null) return (null, _Done(_DoneStage.workout, current.id));
  final finishedHere =
      open[current.id] != true &&
      (group == null || exercises[nextIdx].supersetGroup != group);
  return (
    nextIdx,
    finishedHere
        ? _Done(_DoneStage.exercise, current.id, nextIndex: nextIdx)
        : null,
  );
}

/// Asks for the effort of [targetSet] and saves it; a cleared answer removes
/// the logged RPE, a skipped one leaves it alone.
Future<void> _promptRpe(
  BuildContext context,
  WidgetRef ref, {
  required SetEntryData targetSet,
  required String exerciseName,
  required String setLabel,
}) async {
  final weightFmt = ref.read(weightFormatProvider);
  final performanceSubtitle = targetSet.weightKg > 0
      ? '${weightFmt.format(targetSet.weightKg)} × ${targetSet.reps} reps'
      : (targetSet.reps > 0 ? '${targetSet.reps} reps' : null);

  final target = ref
      .read(workoutTargetsProvider(targetSet.workoutExerciseId))
      .valueOrNull?[targetSet.id];
  final defaultRpeX10 =
      targetSet.rpeX10 ?? targetSet.plannedRpeX10 ?? target?.rpeX10;

  final chosenRpe = await FullScreenRpePicker.show(
    context,
    exerciseName: exerciseName,
    setLabel: setLabel,
    performanceSubtitle: performanceSubtitle,
    initialRpeX10: defaultRpeX10,
  );

  if (chosenRpe != null && context.mounted) {
    await ref
        .read(workoutsRepositoryProvider)
        .updateSet(
          setId: targetSet.id,
          rpeX10: chosenRpe < 0 ? null : chosenRpe,
        );
  }
}

/// `Set 2` / `Set 2 of 4` / `Warm-up 1` for the set at [index] of [sets].
String _setLabel(List<SetEntryData> sets, int index, {bool withTotal = false}) {
  if (index < 0 || index >= sets.length) return 'Set ${index + 1}';
  final n = numberSets(sets)[index];
  if (n.isWarmup) return 'Warm-up ${n.ordinal}';
  return withTotal ? 'Set ${n.ordinal} of ${n.ofKind}' : 'Set ${n.ordinal}';
}

class _EmptyWorkout extends StatelessWidget {
  const _EmptyWorkout({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                WorkoutCircleButton(
                  icon: Icons.close_fullscreen_rounded,
                  tooltip: 'Classic mode',
                  onTap: onExit,
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Add exercises in Classic mode',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
