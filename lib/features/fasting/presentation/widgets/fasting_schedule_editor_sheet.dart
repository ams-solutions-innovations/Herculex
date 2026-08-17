import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../data/local/database.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../../../../widgets/premium_button.dart';
import '../../domain/fasting_plan.dart';
import '../../domain/fasting_schedule_occurrence.dart';
import '../fasting_providers.dart';

/// Add/edit sheet for one [FastingScheduleData] row. Pass [existing] to
/// edit — its id and current values seed the form and a delete action
/// appears; omit it to create a new schedule (defaults to every day at
/// 20:00, 16:8).
class FastingScheduleEditorSheet extends ConsumerStatefulWidget {
  const FastingScheduleEditorSheet({super.key, this.existing});

  final FastingScheduleData? existing;

  @override
  ConsumerState<FastingScheduleEditorSheet> createState() =>
      _FastingScheduleEditorSheetState();
}

class _FastingScheduleEditorSheetState
    extends ConsumerState<FastingScheduleEditorSheet> {
  // Quick Fast is excluded — it has no real target, so it makes no sense as
  // the plan behind a scheduled reminder.
  static const _selectablePlans = [
    FastingPlan.h12,
    FastingPlan.h14,
    FastingPlan.h16,
    FastingPlan.h18,
    FastingPlan.h20,
    FastingPlan.d1,
    FastingPlan.d2,
    FastingPlan.d3,
    FastingPlan.custom,
  ];

  late int _daysOfWeek;
  late TimeOfDay _startTime;
  late FastingPlan _plan;
  late int _customHours;
  late bool _autoStart;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _daysOfWeek = existing.daysOfWeek;
      _startTime = TimeOfDay(
        hour: existing.startTimeMinutes ~/ 60,
        minute: existing.startTimeMinutes % 60,
      );
      _plan = resolveSchedulePlan(existing.planName);
      _customHours = existing.customTargetSeconds != null
          ? existing.customTargetSeconds! ~/ 3600
          : 16;
      _autoStart = existing.autoStart;
      _enabled = existing.enabled;
    } else {
      _daysOfWeek = kAllWeekdays;
      _startTime = const TimeOfDay(hour: 20, minute: 0);
      _plan = FastingPlan.h16;
      _customHours = 16;
      _autoStart = false;
      _enabled = true;
    }
  }

  int get _startTimeMinutes => _startTime.hour * 60 + _startTime.minute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isEditing = widget.existing != null;
    final preview = nextOccurrences(
      daysOfWeek: _daysOfWeek,
      startTimeMinutes: _startTimeMinutes,
      from: DateTime.now(),
      count: 3,
    );

    return HxSheet(
      title: isEditing ? 'Edit Schedule' : 'New Schedule',
      pinnedBottom: Row(
        children: [
          if (isEditing) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text(
                  'DELETE',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: PremiumButton(text: 'SAVE', isPrimary: true, onTap: _save),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REPEAT',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var weekday = 1; weekday <= 7; weekday++)
                _dayToggle(context, weekday),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'TIME',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          _tile(
            context,
            icon: Icons.schedule_rounded,
            label: formatStartTime(_startTimeMinutes),
            onTap: _pickTime,
          ),
          const SizedBox(height: 20),
          Text(
            'PLAN',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plan in _selectablePlans) _planChip(context, plan),
            ],
          ),
          if (_plan == FastingPlan.custom) ...[
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.tune_rounded,
              label: 'Custom: $_customHours h',
              onTap: _pickCustomHours,
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start automatically'),
            subtitle: Text(
              'Tapping the reminder starts the fast right away instead of '
              'just opening the app.',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
            value: _autoStart,
            onChanged: (v) => setState(() => _autoStart = v),
          ),
          if (isEditing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'NEXT REMINDERS',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
            ),
            const SizedBox(height: 8),
            for (final occurrence in preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  DateFormat('E, MMM d · HH:mm').format(occurrence),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: hx.domainFasting),
            const SizedBox(width: 12),
            Text(
              label,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Icon(Icons.edit, size: 14, color: hx.domainFasting),
          ],
        ),
      ),
    );
  }

  Widget _dayToggle(BuildContext context, int weekday) {
    final hx = context.hx;
    final selected = hasWeekday(_daysOfWeek, weekday);
    return GestureDetector(
      onTap: () => setState(() {
        // Toggling the last remaining day back off would leave an
        // unschedulable row — keep at least one day selected always instead
        // of surfacing a validation error.
        final next = toggleWeekday(_daysOfWeek, weekday);
        if (next != 0) _daysOfWeek = next;
      }),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? hx.domainFasting : hx.surfaceContainerLowest,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          kWeekdayAbbrev[weekday - 1].substring(0, 1),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : hx.secondary,
          ),
        ),
      ),
    );
  }

  Widget _planChip(BuildContext context, FastingPlan plan) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final selected = _plan == plan;
    return InkWell(
      onTap: () => setState(() => _plan = plan),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? hx.domainFasting.withValues(alpha: 0.15)
              : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          plan.nameString,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: selected ? hx.domainFasting : hx.secondary,
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickCustomHours() async {
    int tempHours = _customHours;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Custom Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$tempHours hours',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempHours.toDouble(),
                min: 1,
                max: 168,
                divisions: 167,
                activeColor: ctx.hx.domainFasting,
                onChanged: (val) => setDlgState(() => tempHours = val.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tempHours),
              child: const Text('SET DURATION'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _customHours = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final repo = ref.read(fastingRepositoryProvider);
    final scheduler = ref.read(fastingScheduleServiceProvider);
    final existing = widget.existing;
    final customTargetSeconds =
        _plan == FastingPlan.custom ? _customHours * 3600 : null;

    final int id;
    if (existing != null) {
      id = existing.id;
      await repo.updateSchedule(
        id,
        planName: _plan.name,
        customTargetSeconds: customTargetSeconds,
        daysOfWeek: _daysOfWeek,
        startTimeMinutes: _startTimeMinutes,
        enabled: _enabled,
        autoStart: _autoStart,
      );
    } else {
      id = await repo.createSchedule(
        planName: _plan.name,
        customTargetSeconds: customTargetSeconds,
        daysOfWeek: _daysOfWeek,
        startTimeMinutes: _startTimeMinutes,
        autoStart: _autoStart,
      );
    }

    final saved = await repo.schedule(id);
    if (saved != null) await scheduler.rescheduleOne(saved);

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    setState(() => _saving = true);

    await ref.read(fastingScheduleServiceProvider).cancelForSchedule(existing.id);
    await ref.read(fastingRepositoryProvider).deleteSchedule(existing.id);

    if (mounted) Navigator.of(context).pop();
  }
}
