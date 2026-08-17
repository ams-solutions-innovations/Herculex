import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../../../widgets/premium_button.dart';
import '../domain/fasting_plan.dart';
import '../domain/fasting_schedule_occurrence.dart';
import 'fasting_providers.dart';
import 'widgets/fasting_schedule_editor_sheet.dart';

/// `/fasting/schedule` — recurring "notify to start" reminders. Reached from
/// [FastingView]'s header actions.
class FastingScheduleView extends ConsumerWidget {
  const FastingScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final schedulesAsync = ref.watch(fastingSchedulesProvider);

    return HxScreenShell(
      title: 'Fasting Schedule',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: PremiumButton(
          text: 'ADD SCHEDULE',
          isPrimary: true,
          icon: Icons.add_alarm_rounded,
          onTap: () => _openEditor(context),
        ),
      ),
      children: [
        Text(
          "Get a reminder to start a fast on the days and times you choose.",
          style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary),
        ),
        const SizedBox(height: HxSpace.x6),
        schedulesAsync.when(
          data: (schedules) {
            if (schedules.isEmpty) {
              return HxGlass(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.alarm_add_rounded, size: 36, color: hx.outline),
                    const SizedBox(height: 12),
                    Text(
                      "No Schedules Yet",
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Add one to get reminded when it's time to start fasting.",
                      style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                for (final schedule in schedules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ScheduleCard(
                      schedule: schedule,
                      onTap: () => _openEditor(context, existing: schedule),
                      onToggle: (enabled) => _toggle(ref, schedule, enabled),
                      onDismissed: () => _delete(ref, schedule),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    FastingScheduleData? existing,
  }) {
    return HxSheet.show<void>(
      context,
      builder: (_) => FastingScheduleEditorSheet(existing: existing),
    );
  }

  Future<void> _toggle(
    WidgetRef ref,
    FastingScheduleData schedule,
    bool enabled,
  ) async {
    final repo = ref.read(fastingRepositoryProvider);
    await repo.setScheduleEnabled(schedule.id, enabled);
    final updated = await repo.schedule(schedule.id);
    if (updated != null) {
      await ref.read(fastingScheduleServiceProvider).rescheduleOne(updated);
    }
  }

  Future<void> _delete(WidgetRef ref, FastingScheduleData schedule) async {
    await ref.read(fastingScheduleServiceProvider).cancelForSchedule(schedule.id);
    await ref.read(fastingRepositoryProvider).deleteSchedule(schedule.id);
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onTap,
    required this.onToggle,
    required this.onDismissed,
  });

  final FastingScheduleData schedule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final plan = resolveSchedulePlan(schedule.planName);
    final targetSeconds = resolveScheduleTargetSeconds(
      schedule.planName,
      schedule.customTargetSeconds,
    );
    final planLabel = plan == FastingPlan.custom
        ? '${targetSeconds ~/ 3600}h fast'
        : '${plan.nameString} fast';
    final next = schedule.enabled
        ? nextOccurrence(
            daysOfWeek: schedule.daysOfWeek,
            startTimeMinutes: schedule.startTimeMinutes,
            from: DateTime.now(),
          )
        : null;

    return Dismissible(
      key: ValueKey('fasting_schedule_${schedule.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDismissed(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: HxGlass(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: schedule.enabled
                      ? hx.domainFasting.withValues(alpha: 0.15)
                      : hx.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alarm_rounded,
                  color: schedule.enabled ? hx.domainFasting : hx.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatStartTime(schedule.startTimeMinutes)} · '
                      '${formatDaysOfWeek(schedule.daysOfWeek)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planLabel,
                      style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Next: ${DateFormat('E, MMM d · HH:mm').format(next)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: hx.domainFasting),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(value: schedule.enabled, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text("Delete Schedule"),
        content: const Text("Are you sure you want to delete this fasting schedule?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "DELETE",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
