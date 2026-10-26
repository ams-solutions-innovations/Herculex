import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';

/// Modal bottom sheet allowing the user to select either an intermittent
/// (normal) or prolonged (multi-day) fasting protocol.
class FastingPlanPickerSheet extends StatefulWidget {
  const FastingPlanPickerSheet({
    super.key,
    required this.selectedPlan,
    required this.customTargetHours,
    required this.onPlanSelected,
    required this.onCustomHoursChanged,
    this.initialTab,
  });

  final FastingPlan selectedPlan;
  final int customTargetHours;
  final ValueChanged<FastingPlan> onPlanSelected;
  final ValueChanged<int> onCustomHoursChanged;
  final int? initialTab;

  /// Shows the plan picker bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required FastingPlan selectedPlan,
    required int customTargetHours,
    required ValueChanged<FastingPlan> onPlanSelected,
    required ValueChanged<int> onCustomHoursChanged,
    int? initialTab,
  }) {
    return HxSheet.show(
      context,
      builder: (ctx) => FastingPlanPickerSheet(
        selectedPlan: selectedPlan,
        customTargetHours: customTargetHours,
        onPlanSelected: onPlanSelected,
        onCustomHoursChanged: onCustomHoursChanged,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<FastingPlanPickerSheet> createState() => _FastingPlanPickerSheetState();
}

class _FastingPlanPickerSheetState extends State<FastingPlanPickerSheet> {
  late int _tabIndex;
  late int _customHours;

  @override
  void initState() {
    super.initState();
    _customHours = widget.customTargetHours;
    if (widget.initialTab != null) {
      _tabIndex = widget.initialTab!;
    } else {
      _tabIndex = widget.selectedPlan.isProlonged ? 1 : 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxSheet(
      title: 'Select Fasting Plan',
      subtitle: 'Choose an intermittent or prolonged protocol',
      scrollable: true,
      initialSize: 0.78,
      maxSize: 0.94,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HxTopTabs(
            labels: const ['Intermittent', 'Prolonged'],
            index: _tabIndex,
            accent: hx.domainFasting,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
          const SizedBox(height: HxSpace.x4),
          if (_tabIndex == 0) ...[
            Text(
              'NORMAL & INTERMITTENT PROTOCOLS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.secondary,
                letterSpacing: 1.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _planTile(
              context,
              plan: FastingPlan.quickFast,
              tag: 'ELAPSED ONLY',
            ),
            const SizedBox(height: 10),
            for (final plan in FastingPlan.values.where(
              (p) =>
                  p != FastingPlan.quickFast &&
                  !p.isProlonged &&
                  p != FastingPlan.custom,
            )) ...[
              _planTile(context, plan: plan),
              const SizedBox(height: 10),
            ],
            _customPlanTile(context, isProlonged: false),
          ] else ...[
            Row(
              children: [
                Text(
                  'EXTENDED MULTI-DAY PROTOCOLS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.secondary,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: hx.domainFasting.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '1–3 DAYS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.domainFasting,
                      fontSize: 9,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final plan in FastingPlan.values.where((p) => p.isProlonged)) ...[
              _planTile(context, plan: plan),
              const SizedBox(height: 10),
            ],
            _customPlanTile(context, isProlonged: true),
          ],
          const SizedBox(height: HxSpace.x4),
        ],
      ),
    );
  }

  Widget _planTile(
    BuildContext context, {
    required FastingPlan plan,
    String? tag,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isSelected = widget.selectedPlan == plan;

    return InkWell(
      onTap: () {
        Haptics.selection();
        widget.onPlanSelected(plan);
        Navigator.of(context).pop();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    hx.domainFasting.withValues(alpha: hx.isDark ? 0.20 : 0.14),
                    hx.surfaceContainerLowest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? hx.domainFasting.withValues(alpha: 0.25)
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.nameString,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? hx.domainFasting : null,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hx.domainFasting.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: hx.domainFasting,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? hx.domainFasting : Colors.transparent,
                shape: BoxShape.circle,
                border: isSelected
                    ? null
                    : Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _customPlanTile(BuildContext context, {required bool isProlonged}) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isSelected = widget.selectedPlan == FastingPlan.custom;

    return InkWell(
      onTap: () async {
        Haptics.selection();
        await _pickCustomTargetHours();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    hx.domainFasting.withValues(alpha: hx.isDark ? 0.20 : 0.14),
                    hx.surfaceContainerLowest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? hx.domainFasting
                : hx.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? hx.domainFasting.withValues(alpha: 0.25)
                    : hx.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tune_rounded,
                color: isSelected ? hx.domainFasting : hx.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom (${_customHours}h)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? hx.domainFasting : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isProlonged
                        ? 'Set custom prolonged duration (tap to adjust)'
                        : 'Set custom fasting hours (tap to adjust)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? hx.domainFasting : Colors.transparent,
                shape: BoxShape.circle,
                border: isSelected
                    ? null
                    : Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomTargetHours() async {
    int tempHours = _customHours;
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

    if (!mounted || selected == null) return;
    setState(() => _customHours = selected);
    widget.onCustomHoursChanged(selected);
    widget.onPlanSelected(FastingPlan.custom);
    Navigator.of(context).pop();
  }
}
