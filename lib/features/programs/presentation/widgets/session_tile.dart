import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../domain/schedule_status.dart';
import '../../domain/scheduled_workout_row.dart';

/// Colour for a scheduled session's status chip and calendar dot.
Color scheduleStatusColor(String status) => switch (status) {
  ScheduleStatus.done => const Color(0xFF34C759),
  ScheduleStatus.inProgress => const Color(0xFFFF9F0A),
  ScheduleStatus.skipped => AppColors.outlineVariant,
  ScheduleStatus.moved => const Color(0xFFAF52DE),
  _ => AppColors.primary,
};

/// One scheduled session, as shown on the week board and in the day sheet.
///
/// The drag affordance is deliberately split: [dragIndex] wires the handle to
/// the enclosing `ReorderableListView` (reorder within a day), while dragging
/// the tile *body* long-press moves it to another day. Handle-vs-body keeps the
/// two gestures from competing.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.row,
    this.onTap,
    this.dragIndex,
    this.compact = false,
  });

  final ScheduledWorkoutRow row;
  final VoidCallback? onTap;

  /// Index within the enclosing reorderable list; null hides the handle.
  final int? dragIndex;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = scheduleStatusColor(row.status);
    final dimmed = row.isSkipped || row.isDone;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null
              ? null
              : () {
                  Haptics.selection();
                  onTap!();
                },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: compact ? 8 : 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: compact ? 28 : 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: row.isSkipped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _Subtitle(row: row),
                    ],
                  ),
                ),
                if (row.hasTemplateOverride)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                  ),
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: AppColors.outlineVariant,
                      ),
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

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.row});

  final ScheduledWorkoutRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.secondary,
      fontSize: 11,
    );

    final parts = <String>[];
    if (row.template != null) {
      parts.add(row.template!.name);
    } else if (row.isEmpty) {
      parts.add('No exercises yet');
    }
    if (!row.isEmpty) {
      parts.add(
        row.exerciseCount == 1 ? '1 exercise' : '${row.exerciseCount} exercises',
      );
    }
    if (row.status != ScheduleStatus.planned) parts.add(row.statusLabel);

    return Row(
      children: [
        if (row.isEmpty && row.template == null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.error_outline_rounded,
              size: 12,
              color: AppColors.secondary,
            ),
          ),
        Flexible(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
