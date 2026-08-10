import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/premium_button.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../workouts/presentation/template_builder_view.dart';
import '../domain/schedule_status.dart';
import '../domain/scheduled_workout_row.dart';
import 'programs_providers.dart';
import 'widgets/session_tile.dart';
import 'template_picker_sheet.dart';

/// Everything you can do to one day of a block: see its sessions, attach or
/// swap templates, start, skip, move or delete.
class DayDetailSheet extends ConsumerWidget {
  const DayDetailSheet({super.key, required this.date, required this.programId});

  final DateTime date;
  final int? programId;

  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    required int? programId,
  }) {
    return AppBottomSheet.show(
      context,
      builder: (_) => DayDetailSheet(date: date, programId: programId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = ScheduleRange.week(date, programId: programId);
    final byDate = ref.watch(scheduleByDateProvider(range));
    final iso = _iso(date);
    final rows = byDate.value?[iso] ?? const <ScheduledWorkoutRow>[];

    return AppBottomSheet(
      title: DateFormat('EEEE, MMMM d').format(date),
      subtitle: rows.isEmpty
          ? 'Nothing scheduled'
          : rows.length == 1
          ? '1 session'
          : '${rows.length} sessions',
      initialSize: 0.65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.bedtime_outlined,
                    size: 32,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rest day',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a session from the block editor,\nor drag one here from another day.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SessionCard(row: row),
              ),
        ],
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.row});

  final ScheduledWorkoutRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = scheduleStatusColor(row.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
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
                child: Text(
                  row.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  row.statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${row.phaseLabel} · Week ${row.week.weekIndex + 1} of ${row.program.weeks}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          _contentRow(context, ref, theme),
          const SizedBox(height: 14),
          if (ScheduleStatus.isOpen(row.status) && !row.isEmpty)
            PremiumButton(
              text: row.isInProgress ? 'Resume workout' : 'Start workout',
              icon: Icons.play_arrow_rounded,
              onTap: () => _start(context, ref),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.library_books_outlined,
                label: row.isTemplateBacked ? 'Change template' : 'Use template',
                onTap: () => _assignTemplate(context, ref),
              ),
              _ActionChip(
                icon: Icons.add_circle_outline_rounded,
                label: 'New template',
                onTap: () => _createTemplate(context, ref),
              ),
              if (row.isTemplateBacked)
                _ActionChip(
                  icon: Icons.link_off_rounded,
                  label: 'Unlink',
                  onTap: () => _unlink(context, ref),
                ),
              _ActionChip(
                icon: Icons.event_repeat_rounded,
                label: 'Move to…',
                onTap: () => _move(context, ref),
              ),
              if (row.status != ScheduleStatus.skipped)
                _ActionChip(
                  icon: Icons.block_rounded,
                  label: 'Skip',
                  onTap: () => ref
                      .read(programsRepositoryProvider)
                      .setScheduleStatus(row.id, ScheduleStatus.skipped),
                )
              else
                _ActionChip(
                  icon: Icons.undo_rounded,
                  label: 'Un-skip',
                  onTap: () => ref
                      .read(programsRepositoryProvider)
                      .setScheduleStatus(row.id, ScheduleStatus.planned),
                ),
              _ActionChip(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                destructive: true,
                onTap: () => ref
                    .read(programsRepositoryProvider)
                    .deleteScheduledWorkout(row.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contentRow(BuildContext context, WidgetRef ref, ThemeData theme) {
    if (row.isTemplateBacked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.library_books, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.template!.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    row.hasTemplateOverride
                        ? '${row.exerciseCount} exercises · this session only'
                        : '${row.exerciseCount} exercises · linked to every '
                              '${row.title} day',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: row.isEmpty
            ? AppColors.tertiary.withValues(alpha: 0.10)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            row.isEmpty ? Icons.error_outline_rounded : Icons.fitness_center,
            size: 16,
            color: row.isEmpty ? AppColors.tertiary : AppColors.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.isEmpty
                  ? 'No exercises yet — attach a template to fill this session.'
                  : '${row.exerciseCount} exercises set on this day',
              style: theme.textTheme.bodySmall?.copyWith(
                color: row.isEmpty ? AppColors.tertiary : AppColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final service = ref.read(scheduledWorkoutServiceProvider);
    final today = await service.todaysWorkout();
    if (today == null || today.schedule.id != row.id) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only start a session on the day it is scheduled.'),
        ),
      );
      return;
    }
    await service.startScheduledWorkout(today);
    navigator.pop();
  }

  Future<void> _assignTemplate(BuildContext context, WidgetRef ref) async {
    final picked = await TemplatePickerSheet.show(context);
    if (picked == null || !context.mounted) return;
    await _applyTemplate(context, ref, picked.id);
  }

  Future<void> _createTemplate(BuildContext context, WidgetRef ref) async {
    final created = await TemplateBuilderView.show(
      context,
      returnsSelection: true,
    );
    if (created == null || !context.mounted) return;
    await _applyTemplate(context, ref, created.id);
  }

  /// Asks whether the template applies to this occurrence only or to every
  /// future session of this program day — the difference between a one-off swap
  /// and re-pointing the live link.
  Future<void> _applyTemplate(
    BuildContext context,
    WidgetRef ref,
    int templateId,
  ) async {
    final scope = await showModalBottomSheet<_TemplateScope>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AppBottomSheet(
        scrollable: false,
        title: 'Apply to',
        subtitle: 'This template can cover one session or all of them.',
        child: Column(
          children: [
            _ScopeOption(
              icon: Icons.today_rounded,
              title: 'This session only',
              subtitle: 'Swap just ${DateFormat('MMM d').format(row.date)}.',
              onTap: () => Navigator.pop(context, _TemplateScope.thisSession),
            ),
            const SizedBox(height: 8),
            _ScopeOption(
              icon: Icons.repeat_rounded,
              title: 'Every future ${row.title} day',
              subtitle: 'Re-links the program day; past sessions are untouched.',
              onTap: () => Navigator.pop(context, _TemplateScope.everyFuture),
            ),
          ],
        ),
      ),
    );
    if (scope == null) return;

    final repo = ref.read(programsRepositoryProvider);
    Haptics.success();
    if (scope == _TemplateScope.thisSession) {
      await repo.setScheduleTemplateOverride(row.id, templateId);
    } else {
      await repo.setProgramDayTemplate(row.day.id, templateId);
      await repo.setScheduleTemplateOverride(row.id, null);
      await repo.rematerializeProgram(row.program.id);
    }
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(programsRepositoryProvider);
    if (row.hasTemplateOverride) {
      await repo.setScheduleTemplateOverride(row.id, null);
      return;
    }
    await repo.setProgramDayTemplate(row.day.id, null);
    await repo.rematerializeProgram(row.program.id);
  }

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: row.date,
      firstDate: row.date.subtract(const Duration(days: 180)),
      lastDate: row.date.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    await ref
        .read(programsRepositoryProvider)
        .moveScheduledWorkout(scheduleId: row.id, newDate: picked);
  }
}

enum _TemplateScope { thisSession, everyFuture }

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : AppColors.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
