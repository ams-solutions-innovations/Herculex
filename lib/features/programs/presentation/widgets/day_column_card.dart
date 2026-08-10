import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../data/local/database.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../domain/scheduled_workout_row.dart';
import '../programs_providers.dart';
import 'session_tile.dart';

/// One day of the week board: a header that accepts sessions dragged in from
/// other days, and a reorderable list of the sessions already on it.
class DayColumnCard extends ConsumerWidget {
  const DayColumnCard({
    super.key,
    required this.date,
    required this.rows,
    required this.onOpenDay,
    required this.onOpenSession,
    this.event,
  });

  final DateTime date;
  final List<ScheduledWorkoutRow> rows;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<ScheduledWorkoutRow> onOpenSession;

  /// A vacation/rest/deload range covering this date, if any.
  final ExternalEventData? event;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          // Refuse a drop onto the day the session already sits on.
          !rows.any((r) => r.id == details.data),
      onAcceptWithDetails: (details) async {
        Haptics.success();
        await ref
            .read(programsRepositoryProvider)
            .moveScheduledWorkout(scheduleId: details.data, newDate: date);
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.primary.withValues(alpha: 0.10)
                : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hovering
                  ? AppColors.primary
                  : _isToday
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
              width: hovering || _isToday ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme),
              if (event != null) ...[
                const SizedBox(height: 8),
                _eventBanner(theme),
              ],
              const SizedBox(height: 8),
              if (rows.isEmpty)
                _restRow(theme)
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: rows.length,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  ),
                  onReorder: (oldIndex, newIndex) async {
                    Haptics.light();
                    await ref
                        .read(programsRepositoryProvider)
                        .reorderScheduledOnDate(
                          dateIso: rows.first.dateIso,
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        );
                  },
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return Padding(
                      key: ValueKey('schedule_${row.id}'),
                      padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 8),
                      // Long-pressing the body drags to another day; the tile's
                      // own handle drives the reorder above. Splitting the two
                      // gestures keeps them from competing.
                      child: LongPressDraggable<int>(
                        data: row.id,
                        onDragStarted: Haptics.medium,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width - 80,
                            child: Opacity(
                              opacity: 0.9,
                              child: SessionTile(row: row, compact: true),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: SessionTile(row: row, compact: true),
                        ),
                        child: SessionTile(
                          row: row,
                          dragIndex: rows.length > 1 ? i : null,
                          onTap: () => onOpenSession(row),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _isToday
                ? AppColors.primary
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('E').format(date).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.5,
                  color: _isToday ? Colors.white : AppColors.secondary,
                ),
              ),
              Text(
                '${date.day}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: _isToday ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            DateFormat('EEEE').format(date),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
          tooltip: 'Add a session',
          onPressed: () => onOpenDay(date),
        ),
      ],
    );
  }

  Widget _eventBanner(ThemeData theme) {
    final label = switch (event!.type) {
      'vacation' => 'Vacation',
      'deload' => 'Deload',
      'rest' => 'Rest',
      _ => event!.type,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access_rounded, size: 14, color: AppColors.tertiary),
          const SizedBox(width: 6),
          Text(
            event!.notes?.isNotEmpty == true ? '$label · ${event!.notes}' : label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _restRow(ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpenDay(date),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        child: Text(
          'Rest day',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
      ),
    );
  }
}
