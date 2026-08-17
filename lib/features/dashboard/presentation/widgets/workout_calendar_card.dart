import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';
/// Interactive Workout Calendar widget on the dashboard (§18).
/// Offers Day and Week view toggle modes for viewing scheduled workouts and completed sessions.
class WorkoutCalendarCard extends ConsumerWidget {
  const WorkoutCalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(calendarViewModeProvider);
    final selectedDate = ref.watch(calendarSelectedDateProvider);

    return dashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  dashboardTitle(context, "Workout Calendar"),
                ],
              ),
              // Segmented view switcher (Day vs Week)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModeButton(
                      ref: ref,
                      label: "Week",
                      mode: CalendarViewMode.week,
                      activeMode: viewMode,
                    ),
                    _buildModeButton(
                      ref: ref,
                      label: "Day",
                      mode: CalendarViewMode.day,
                      activeMode: viewMode,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (viewMode == CalendarViewMode.week)
            _buildWeekView(context, ref, selectedDate)
          else
            _buildDayView(context, ref, selectedDate),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required WidgetRef ref,
    required String label,
    required CalendarViewMode mode,
    required CalendarViewMode activeMode,
  }) {
    final isActive = mode == activeMode;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        ref.read(calendarViewModeProvider.notifier).state = mode;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : AppColors.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekView(BuildContext context, WidgetRef ref, DateTime selectedDate) {
    final weekSummaryAsync = ref.watch(weekCalendarSummaryProvider(selectedDate));

    return weekSummaryAsync.when(
      data: (summaries) {
        final selectedSummary = summaries.firstWhere(
          (s) => s.date.year == selectedDate.year &&
              s.date.month == selectedDate.month &&
              s.date.day == selectedDate.day,
          orElse: () => summaries.firstWhere((s) => s.isToday, orElse: () => summaries.first),
        );

        return Column(
          children: [
            // 7-day pill strip
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in summaries) ...[
                  _buildDayPill(context, ref, day, selectedDate),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Details card for selected day
            _buildDayDetailsCard(context, ref, selectedSummary),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      error: (e, _) => Text('Error loading calendar: $e'),
    );
  }

  Widget _buildDayPill(BuildContext context, WidgetRef ref, CalendarDaySummary summary, DateTime selectedDate) {
    final isSelected = summary.date.year == selectedDate.year &&
        summary.date.month == selectedDate.month &&
        summary.date.day == selectedDate.day;

    final dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final dayLabel = dayLetters[summary.date.weekday - 1];

    Color pillBg = AppColors.surfaceContainer;
    Color borderCol = Colors.transparent;
    if (isSelected) {
      pillBg = AppColors.primaryContainer.withValues(alpha: 0.4);
      borderCol = AppColors.primary;
    } else if (summary.isToday) {
      borderCol = AppColors.primary.withValues(alpha: 0.5);
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          ref.read(calendarSelectedDateProvider.notifier).state = summary.date;
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol, width: isSelected ? 1.5 : 1.0),
          ),
          child: Column(
            children: [
              Text(
                dayLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.date.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: summary.isToday || isSelected ? FontWeight.bold : FontWeight.w500,
                  color: summary.isToday ? AppColors.primary : null,
                ),
              ),
              const SizedBox(height: 6),
              // Status Indicator Dot
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (summary.hasCompleted)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (summary.hasScheduled)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayDetailsCard(BuildContext context, WidgetRef ref, CalendarDaySummary summary) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('EEEE, MMM d').format(summary.date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                summary.isToday ? 'Today ($dateStr)' : dateStr,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (summary.hasCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Workout Completed',
                    style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!summary.hasScheduled && !summary.hasCompleted)
            Text(
              'Rest Day — No workouts scheduled.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
            ),
          if (summary.hasScheduled) ...[
            for (final sched in summary.scheduledWorkouts) ...[
              Row(
                children: [
                  Icon(
                    sched.status == 'done' ? Icons.check_circle : Icons.schedule,
                    color: sched.status == 'done' ? Colors.green : AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Scheduled Workout (${sched.status.toUpperCase()})',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (summary.hasCompleted) ...[
            const SizedBox(height: 6),
            for (final sess in summary.completedSessions) ...[
              InkWell(
                onTap: () => context.push('/workout-history/${sess.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.fitness_center, color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sess.notes != null && sess.notes!.isNotEmpty
                              ? sess.notes!
                              : 'Workout Session #${sess.id}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm').format(sess.startedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.secondary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDayView(BuildContext context, WidgetRef ref, DateTime selectedDate) {
    final theme = Theme.of(context);
    final weekSummaryAsync = ref.watch(weekCalendarSummaryProvider(selectedDate));

    return weekSummaryAsync.when(
      data: (summaries) {
        final summary = summaries.firstWhere(
          (s) => s.date.year == selectedDate.year &&
              s.date.month == selectedDate.month &&
              s.date.day == selectedDate.day,
          orElse: () => summaries.firstWhere((s) => s.isToday, orElse: () => summaries.first),
        );

        return Column(
          children: [
            // Date Navigation Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    Haptics.light();
                    ref.read(calendarSelectedDateProvider.notifier).state =
                        selectedDate.subtract(const Duration(days: 1));
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        summary.isToday ? 'Today' : DateFormat('EEEE').format(selectedDate),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('MMM d, yyyy').format(selectedDate),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    Haptics.light();
                    ref.read(calendarSelectedDateProvider.notifier).state =
                        selectedDate.add(const Duration(days: 1));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDayDetailsCard(context, ref, summary),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
