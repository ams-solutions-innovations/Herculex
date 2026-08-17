import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../domain/fasting_plan.dart';

/// Plan picker for starting a fast. Purely presentational — the parent
/// [FastingView] owns the selection state so the pinned "Start Fast" button
/// (outside this panel, always on screen) can read it without a controller.
class StartFastPanel extends StatelessWidget {
  const StartFastPanel({
    super.key,
    required this.selectedPlan,
    required this.customTargetHours,
    required this.customStartTime,
    required this.onPlanSelected,
    required this.onCustomHoursChanged,
    required this.onCustomStartTimeChanged,
  });

  final FastingPlan selectedPlan;
  final int customTargetHours;
  final DateTime? customStartTime;
  final ValueChanged<FastingPlan> onPlanSelected;
  final ValueChanged<int> onCustomHoursChanged;
  final ValueChanged<DateTime?> onCustomStartTimeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final format = DateFormat('HH:mm (MMM d)');
    final startTimeDisplay =
        customStartTime != null ? format.format(customStartTime!) : "Now";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                "READY TO START FASTING?",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: hx.domainFasting,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Select a plan aligned with your daily flow.",
                style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => _pickCustomStartTime(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: hx.domainFasting),
                const SizedBox(width: 12),
                Text("Start time:",
                    style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary)),
                const Spacer(),
                Text(
                  startTimeDisplay,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: hx.domainFasting),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: hx.domainFasting),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Quick Fast leads the list — first choice, elapsed-only once active.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _planTile(context, FastingPlan.quickFast),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            "INTERMITTENT",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
        ),
        const SizedBox(height: 12),
        for (final plan in FastingPlan.values.where(
          (p) => p != FastingPlan.quickFast && !p.isProlonged && p != FastingPlan.custom,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _planTile(context, plan),
          ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "PROLONGED",
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: hx.domainFasting.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "1–3 DAYS",
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: hx.domainFasting, fontSize: 9, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final plan in FastingPlan.values.where((p) => p.isProlonged))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _planTile(context, plan),
          ),
        const SizedBox(height: 12),
        _customPlanTile(context),
      ],
    );
  }

  Widget _planTile(BuildContext context, FastingPlan plan) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isSelected = selectedPlan == plan;
    return InkWell(
      onTap: () => onPlanSelected(plan),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? hx.domainFasting.withValues(alpha: 0.1)
              : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? hx.domainFasting.withValues(alpha: 0.2)
                    : hx.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                plan == FastingPlan.quickFast
                    ? Icons.bolt_rounded
                    : plan.isProlonged
                        ? Icons.bedtime_outlined
                        : Icons.hourglass_empty,
                color: isSelected ? hx.domainFasting : hx.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.nameString,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(plan.description,
                      style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: hx.domainFasting, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _customPlanTile(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isSelected = selectedPlan == FastingPlan.custom;
    return InkWell(
      onTap: () {
        onPlanSelected(FastingPlan.custom);
        _pickCustomTargetHours(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? hx.domainFasting.withValues(alpha: 0.1)
              : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? hx.domainFasting.withValues(alpha: 0.2)
                    : hx.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tune_rounded,
                  color: isSelected ? hx.domainFasting : hx.onSurfaceVariant,
                  size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Custom (${customTargetHours}h)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Set your own target hours (tap to change)',
                      style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: hx.domainFasting, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomTargetHours(BuildContext context) async {
    int tempHours = customTargetHours;
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
              Text('$tempHours hours',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Slider(
                value: tempHours.toDouble(),
                min: 1,
                max: 168,
                divisions: 167,
                activeColor: AppColors.primary,
                onChanged: (val) => setDlgState(() => tempHours = val.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tempHours),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('SET DURATION'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) onCustomHoursChanged(selected);
  }

  Future<void> _pickCustomStartTime(BuildContext context) async {
    final now = DateTime.now();
    final initialTime = TimeOfDay.fromDateTime(customStartTime ?? now);
    final pickedTime = await showTimePicker(context: context, initialTime: initialTime);
    if (pickedTime == null) return;

    var dt = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
    if (dt.isAfter(now)) {
      // A time later today can only mean the fast began yesterday at that time.
      dt = dt.subtract(const Duration(days: 1));
    }
    onCustomStartTimeChanged(dt);
  }
}
