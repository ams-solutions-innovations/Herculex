import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens/tokens.dart';
import '../../nutrition/presentation/meal_slots_provider.dart';
import 'notification_settings_provider.dart';

class NotificationSettingsView extends ConsumerWidget {
  const NotificationSettingsView({super.key});

  Future<void> _pickMealTime(
    BuildContext context,
    WidgetRef ref,
    String slotKey,
    String currentTimeHHMM,
  ) async {
    final parts = currentTimeHHMM.split(':');
    final initialHour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 12 : 12;
    final initialMinute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      await ref
          .read(notificationSettingsProvider.notifier)
          .setMealTime(slotKey, '$h:$m');
    }
  }

  Future<void> _pickDailyLogTime(
    BuildContext context,
    WidgetRef ref,
    String currentTimeHHMM,
  ) async {
    final parts = currentTimeHHMM.split(':');
    final initialHour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 21 : 21;
    final initialMinute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      await ref
          .read(notificationSettingsProvider.notifier)
          .setDailyLogTime('$h:$m');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final mealSlots = ref.watch(mealSlotsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text(
            'Control push reminders and background notifications for your meals, fasting, supplements, and workouts.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.hx.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // ── Meals Section ──────────────────────────────────────────────────
          _SectionHeader('Meals'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: Icons.restaurant_menu_rounded,
                title: 'Meal Reminders',
                subtitle: 'Send reminders for scheduled meal slots',
                value: settings.mealRemindersEnabled,
                onChanged: notifier.setMealRemindersEnabled,
              ),
              if (settings.mealRemindersEnabled) ...[
                _SettingsDivider(),
                for (final slot in mealSlots) ...[
                  _MealSlotRow(
                    icon: slot.icon,
                    label: slot.label,
                    timeHHMM: settings.mealTimeFor(slot.key),
                    isEnabled: settings.isMealEnabled(slot.key),
                    onToggle: (val) =>
                        notifier.setMealSlotEnabled(slot.key, val),
                    onPickTime: () => _pickMealTime(
                      context,
                      ref,
                      slot.key,
                      settings.mealTimeFor(slot.key),
                    ),
                  ),
                  if (slot != mealSlots.last) _SettingsDivider(),
                ],
              ],
            ],
          ),
          const SizedBox(height: 24),

          // ── Fasting Section ────────────────────────────────────────────────
          _SectionHeader('Fasting'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: Icons.timer_outlined,
                title: 'Fasting Goal Reached',
                subtitle: 'Alert when your target fast window is achieved',
                value: settings.fastingGoalReachedEnabled,
                onChanged: notifier.setFastingGoalReachedEnabled,
              ),
              _SettingsDivider(),
              _SettingsSwitchTile(
                icon: Icons.calendar_month_outlined,
                title: 'Fasting Schedule Reminders',
                subtitle: 'Reminders when scheduled fast windows begin',
                value: settings.fastingScheduleRemindersEnabled,
                onChanged: notifier.setFastingScheduleRemindersEnabled,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Supplements Section ────────────────────────────────────────────
          _SectionHeader('Supplements'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: Icons.medication_outlined,
                title: 'Daily Supplement Reminders',
                subtitle: 'Remind at times configured on your supplements',
                value: settings.supplementRemindersEnabled,
                onChanged: notifier.setSupplementRemindersEnabled,
              ),
              _SettingsDivider(),
              _SettingsSwitchTile(
                icon: Icons.fitness_center_rounded,
                title: 'Post-Workout Supplements',
                subtitle:
                    'Prompt for post-workout supplements when workout ends',
                value: settings.postWorkoutSupplementEnabled,
                onChanged: notifier.setPostWorkoutSupplementEnabled,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Workouts Section ───────────────────────────────────────────────
          _SectionHeader('Workouts'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'Live Workout Notification',
                subtitle:
                    'Ongoing tray notification with live timer & quick logging',
                value: settings.activeWorkoutBannerEnabled,
                onChanged: notifier.setActiveWorkoutBannerEnabled,
              ),
              _SettingsDivider(),
              _SettingsSwitchTile(
                icon: Icons.hourglass_bottom_rounded,
                title: 'Rest Timer Alerts',
                subtitle: 'Alert and sound when rest interval ends',
                value: settings.restTimerAlertsEnabled,
                onChanged: notifier.setRestTimerAlertsEnabled,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Daily Habits Section ───────────────────────────────────────────
          _SectionHeader('Daily Habits & Log'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: Icons.fact_check_outlined,
                title: 'Evening Log Reminder',
                subtitle: 'Remind to log missing meals and review daily stats',
                value: settings.dailyLogReminderEnabled,
                onChanged: notifier.setDailyLogReminderEnabled,
              ),
              if (settings.dailyLogReminderEnabled) ...[
                _SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 20,
                        color: context.hx.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reminder Time',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'When to trigger the evening reminder',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.hx.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => _pickDailyLogTime(
                          context,
                          ref,
                          settings.dailyLogTimeHHMM,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.hx.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: context.hx.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            settings.dailyLogTimeHHMM,
                            style: TextStyle(
                              color: context.hx.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.hx.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      color: context.hx.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.hx.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.hx.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MealSlotRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String timeHHMM;
  final bool isEnabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  const _MealSlotRow({
    required this.icon,
    required this.label,
    required this.timeHHMM,
    required this.isEnabled,
    required this.onToggle,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isEnabled
                ? context.hx.primary
                : context.hx.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isEnabled
                    ? theme.colorScheme.onSurface
                    : context.hx.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          InkWell(
            onTap: isEnabled ? onPickTime : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isEnabled
                    ? context.hx.primary.withValues(alpha: 0.12)
                    : context.hx.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEnabled
                      ? context.hx.primary.withValues(alpha: 0.3)
                      : context.hx.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: isEnabled
                        ? context.hx.primary
                        : context.hx.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    timeHHMM,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isEnabled
                          ? context.hx.primary
                          : context.hx.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: isEnabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
