import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_plan_picker_sheet.dart';
import 'package:intl/intl.dart';

/// Plan picker for starting a fast. Purely presentational — the parent
/// [FastingView] owns the selection state so the pinned "Start Fast" button
/// (outside this panel, always on screen) can read it without a controller.
///
/// Fast selection (both normal intermittent and prolonged multi-day fasts)
/// is presented in a modal bottom sheet ([FastingPlanPickerSheet]) to keep the
/// fasting screen focused and uncluttered.
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
    final startTimeDisplay = customStartTime != null
        ? format.format(customStartTime!)
        : "Now";

    final isQuick = selectedPlan == FastingPlan.quickFast;
    final isProlonged = selectedPlan.isProlonged;
    final isCustom = selectedPlan == FastingPlan.custom;

    final categoryLabel = isProlonged
        ? 'PROLONGED'
        : isQuick
        ? 'OPEN ENDED'
        : isCustom
        ? 'CUSTOM'
        : 'INTERMITTENT';

    final displayName = isCustom
        ? 'Custom (${customTargetHours}h)'
        : selectedPlan.nameString;

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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hx.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Selected Plan Card (Tap to open bottom sheet) ──
        InkWell(
          onTap: () => _openPlanPicker(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  hx.domainFasting.withValues(alpha: hx.isDark ? 0.22 : 0.15),
                  hx.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hx.domainFasting.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hx.domainFasting.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        categoryLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.domainFasting,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Change Plan",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hx.domainFasting,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: hx.domainFasting,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: hx.domainFasting.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isQuick
                            ? Icons.bolt_rounded
                            : isProlonged
                            ? Icons.bedtime_outlined
                            : isCustom
                            ? Icons.tune_rounded
                            : Icons.hourglass_empty,
                        color: hx.domainFasting,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: hx.domainFasting,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedPlan.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hx.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Quick Select Buttons (Intermittent vs Prolonged) ──
        Row(
          children: [
            Expanded(
              child: _categoryButton(
                context,
                title: "Intermittent",
                subtitle: "Daily protocols",
                icon: Icons.hourglass_empty,
                isSelected: !isProlonged,
                onTap: () => _openPlanPicker(context, initialTab: 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _categoryButton(
                context,
                title: "Prolonged",
                subtitle: "1–3 Days",
                icon: Icons.bedtime_outlined,
                isSelected: isProlonged,
                onTap: () => _openPlanPicker(context, initialTab: 1),
              ),
            ),
          ],
        ),

        if (isCustom) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _pickCustomTargetHours(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: hx.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hx.domainFasting.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: hx.domainFasting),
                  const SizedBox(width: 12),
                  Text(
                    "Target duration:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hx.secondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "$customTargetHours hours",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hx.domainFasting,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: hx.domainFasting),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // ── Start Time Picker ──
        InkWell(
          onTap: () => _pickCustomStartTime(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hx.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: hx.domainFasting),
                const SizedBox(width: 12),
                Text(
                  "Start time:",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hx.secondary,
                  ),
                ),
                const Spacer(),
                Text(
                  startTimeDisplay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hx.domainFasting,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: hx.domainFasting),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? hx.domainFasting.withValues(alpha: 0.6)
                : hx.outlineVariant.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? hx.domainFasting : hx.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? hx.domainFasting : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isSelected ? hx.domainFasting : hx.secondary,
            ),
          ],
        ),
      ),
    );
  }

  void _openPlanPicker(BuildContext context, {int? initialTab}) {
    FastingPlanPickerSheet.show(
      context,
      selectedPlan: selectedPlan,
      customTargetHours: customTargetHours,
      onPlanSelected: onPlanSelected,
      onCustomHoursChanged: onCustomHoursChanged,
      initialTab: initialTab,
    );
  }

  Future<void> _pickCustomTargetHours(BuildContext context) async {
    int tempHours = customTargetHours;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Custom Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$tempHours hours',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
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
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;

    var dt = DateTime(
      now.year,
      now.month,
      now.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (dt.isAfter(now)) {
      // A time later today can only mean the fast began yesterday at that time.
      dt = dt.subtract(const Duration(days: 1));
    }
    onCustomStartTimeChanged(dt);
  }
}
