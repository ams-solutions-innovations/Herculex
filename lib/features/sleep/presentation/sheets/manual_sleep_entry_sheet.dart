// lib/features/sleep/presentation/sheets/manual_sleep_entry_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/sleep/application/sleep_providers.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';

/// Modal bottom sheet allowing manual entry or editing of nightly sleep telemetry.
class ManualSleepEntrySheet extends ConsumerStatefulWidget {
  final SleepRecord? initialRecord;
  final String dateIso;

  const ManualSleepEntrySheet({
    super.key,
    this.initialRecord,
    required this.dateIso,
  });

  static Future<void> show(
    BuildContext context, {
    SleepRecord? initialRecord,
    required String dateIso,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ManualSleepEntrySheet(initialRecord: initialRecord, dateIso: dateIso),
    );
  }

  @override
  ConsumerState<ManualSleepEntrySheet> createState() =>
      _ManualSleepEntrySheetState();
}

class _ManualSleepEntrySheetState extends ConsumerState<ManualSleepEntrySheet> {
  late double _hours;
  late double _deepHours;
  late double _remHours;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hours = widget.initialRecord?.totalHours ?? 8.0;
    _deepHours = widget.initialRecord?.stages != null
        ? widget.initialRecord!.stages!.deepMinutes / 60.0
        : 1.5;
    _remHours = widget.initialRecord?.stages != null
        ? widget.initialRecord!.stages!.remMinutes / 60.0
        : 1.8;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(sleepRepositoryProvider);

    await repo.saveManualSleep(
      dateIso: widget.dateIso,
      totalHours: _hours,
      deepHours: _deepHours > 0 ? _deepHours : null,
      remHours: _remHours > 0 ? _remHours : null,
    );

    ref.invalidate(todaySleepProvider);
    ref.invalidate(selectedSleepRecordProvider);
    ref.invalidate(sleepHistoryProvider);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();

    AppNotice.show(
      context,
      'Sleep logged for ${widget.dateIso} (${_hours.toStringAsFixed(1)}h)',
      kind: AppNoticeKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GlassContainer(
        borderRadius: 24.0,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Log Nightly Sleep',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  widget.dateIso,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Duration Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL SLEEP DURATION',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_hours.toStringAsFixed(1)} hrs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
            Slider(
              value: _hours,
              min: 3.0,
              max: 12.0,
              divisions: 36, // 0.25h increments
              activeColor: const Color(0xFF6366F1),
              onChanged: (v) => setState(() => _hours = v),
            ),
            const SizedBox(height: 16),

            // Deep sleep slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DEEP SLEEP (RESTORE)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  '${_deepHours.toStringAsFixed(1)} hrs',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF818CF8),
                  ),
                ),
              ],
            ),
            Slider(
              value: _deepHours.clamp(0.0, _hours),
              min: 0.0,
              max: _hours,
              divisions: 20,
              activeColor: const Color(0xFF818CF8),
              onChanged: (v) => setState(() => _deepHours = v),
            ),
            const SizedBox(height: 16),

            // REM sleep slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'REM SLEEP (CNS DRIVE)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  '${_remHours.toStringAsFixed(1)} hrs',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFA855F7),
                  ),
                ),
              ],
            ),
            Slider(
              value: _remHours.clamp(0.0, _hours),
              min: 0.0,
              max: _hours,
              divisions: 20,
              activeColor: const Color(0xFFA855F7),
              onChanged: (v) => setState(() => _remHours = v),
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  _saving ? 'Saving...' : 'Save Sleep Record',
                  style: const TextStyle(
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
