import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/steps/application/steps_providers.dart';
import 'package:herculex/features/steps/domain/step_record.dart';

/// Modal bottom sheet allowing manual entry or editing of daily step telemetry.
class ManualStepEntrySheet extends ConsumerStatefulWidget {
  final StepRecord? initialRecord;
  final String dateIso;

  const ManualStepEntrySheet({
    super.key,
    this.initialRecord,
    required this.dateIso,
  });

  static Future<void> show(
    BuildContext context, {
    StepRecord? initialRecord,
    required String dateIso,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ManualStepEntrySheet(initialRecord: initialRecord, dateIso: dateIso),
    );
  }

  @override
  ConsumerState<ManualStepEntrySheet> createState() =>
      _ManualStepEntrySheetState();
}

class _ManualStepEntrySheetState extends ConsumerState<ManualStepEntrySheet> {
  late double _steps;
  late double _goal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _steps = (widget.initialRecord?.stepCount ?? 8000).toDouble();
    _goal = (widget.initialRecord?.goal ?? 10000).toDouble();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(stepRepositoryProvider);

    final stepInt = _steps.round();
    final goalInt = _goal.round();

    await repo.saveManualSteps(
      dateIso: widget.dateIso,
      stepCount: stepInt,
      goal: goalInt,
    );

    // Update global goal if changed
    await repo.setDailyGoal(goalInt);
    ref.read(stepGoalProvider.notifier).state = goalInt;

    ref.invalidate(todayStepsProvider);
    ref.invalidate(selectedStepRecordProvider);
    ref.invalidate(stepHistoryProvider);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();

    AppNotice.show(
      context,
      'Steps logged for ${widget.dateIso} ($stepInt steps)',
      kind: AppNoticeKind.success,
    );
  }

  String _formatNumber(int val) {
    return val.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final estimatedKm = (_steps * 0.000762).toStringAsFixed(1);
    final estimatedKcal = (_steps * 0.04).round();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GlassContainer(
        borderRadius: 24.0,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOG DAILY STEPS',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: const Color(0xFFF59E0B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.dateIso,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '~ $estimatedKm km · $estimatedKcal kcal',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Step count slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Step Count',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_formatNumber(_steps.round())} steps',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            Slider(
              value: _steps.clamp(0.0, 35000.0),
              min: 0.0,
              max: 35000.0,
              divisions: 70,
              activeColor: const Color(0xFFF59E0B),
              inactiveColor: AppColors.surfaceContainerLowest,
              onChanged: (val) => setState(() => _steps = val),
            ),
            const SizedBox(height: 16),

            // Goal target slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Daily Step Goal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_formatNumber(_goal.round())} target',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Slider(
              value: _goal.clamp(4000.0, 25000.0),
              min: 4000.0,
              max: 25000.0,
              divisions: 42,
              activeColor: const Color(0xFF10B981),
              inactiveColor: AppColors.surfaceContainerLowest,
              onChanged: (val) => setState(() => _goal = val),
            ),
            const SizedBox(height: 24),

            // Save CTA
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Save Steps',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
