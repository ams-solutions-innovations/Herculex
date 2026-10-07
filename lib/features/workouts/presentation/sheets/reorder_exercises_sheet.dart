import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';

/// A calm, dedicated list for changing the order of the session's exercises.
///
/// Reordering used to happen in place: the moment a drag began, every full
/// exercise card collapsed into a compact pill under the user's finger, so
/// the whole list jumped mid-gesture. Here the list is compact from the
/// start and only the row being dragged moves.
///
/// Linked exercises (superset / tri-set / giant set) are one row and move as
/// one unit. Returns the new order as workout-exercise ids, or null when the
/// user closes the sheet without saving.
class ReorderExercisesSheet extends StatefulWidget {
  const ReorderExercisesSheet({
    super.key,
    required this.groups,
    required this.exerciseFor,
  });

  /// The session's exercises bucketed into drag units, in current order.
  final List<List<WorkoutExerciseData>> groups;
  final ExerciseCatalogData Function(WorkoutExerciseData) exerciseFor;

  static Future<List<int>?> show(
    BuildContext context, {
    required List<List<WorkoutExerciseData>> groups,
    required ExerciseCatalogData Function(WorkoutExerciseData) exerciseFor,
  }) {
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReorderExercisesSheet(groups: groups, exerciseFor: exerciseFor),
    );
  }

  @override
  State<ReorderExercisesSheet> createState() => _ReorderExercisesSheetState();
}

class _ReorderExercisesSheetState extends State<ReorderExercisesSheet> {
  late final List<List<WorkoutExerciseData>> _groups = [...widget.groups];
  bool _changed = false;

  void _save() {
    Navigator.of(context).pop(
      _changed
          ? [
              for (final group in _groups)
                for (final row in group) row.id,
            ]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hx.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reorder exercises',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Hold and drag a row',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hx.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(onPressed: _save, child: const Text('Done')),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _groups.length,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, _, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (_, _) => Material(
                    elevation: 8 * Curves.easeOut.transform(animation.value),
                    color: Colors.transparent,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                    child: child,
                  ),
                ),
                onReorderStart: (_) => Haptics.medium(),
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final moved = _groups.removeAt(oldIndex);
                    _groups.insert(newIndex, moved);
                    _changed = true;
                  });
                },
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  return Padding(
                    key: ValueKey('reorder_group_${group.first.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ReorderableDelayedDragStartListener(
                      index: index,
                      child: _GroupRow(
                        index: index,
                        members: group,
                        exerciseFor: widget.exerciseFor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.index,
    required this.members,
    required this.exerciseFor,
  });

  final int index;
  final List<WorkoutExerciseData> members;
  final ExerciseCatalogData Function(WorkoutExerciseData) exerciseFor;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final linked = members.length > 1;
    final label = switch (members.length) {
      2 => 'SUPERSET',
      3 => 'TRI-SET',
      _ => 'GIANT SET',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: linked
              ? hx.primary.withValues(alpha: 0.4)
              : hx.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: hx.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (linked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: hx.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                for (var j = 0; j < members.length; j++)
                  Padding(
                    padding: EdgeInsets.only(top: j == 0 ? 0 : 6),
                    child: _MemberLine(
                      member: members[j],
                      exercise: exerciseFor(members[j]),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.drag_indicator, color: hx.secondary),
        ],
      ),
    );
  }
}

class _MemberLine extends ConsumerWidget {
  const _MemberLine({required this.member, required this.exercise});

  final WorkoutExerciseData member;
  final ExerciseCatalogData exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final sets =
        ref.watch(setsForWorkoutExerciseProvider(member.id)).valueOrNull ??
        const <SetEntryData>[];
    final working = sets.where((s) => !s.isWarmup).length;
    return Row(
      children: [
        ExerciseArtwork(
          exercise: exercise,
          size: 32,
          radius: 10,
          equipmentVariant: member.equipmentVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            exercise.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (sets.isNotEmpty)
          Text(
            '$working ${working == 1 ? 'set' : 'sets'}',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
      ],
    );
  }
}
