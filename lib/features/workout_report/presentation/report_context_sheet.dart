import 'package:flutter/material.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';

Future<ReportReason?> showReportReasonSheet(
  BuildContext context,
) => showModalBottomSheet<ReportReason>(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reason for this change',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Optional. Helps your training report understand the adjustment.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final reason in ReportReason.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _reasonIcon(reason),
                    size: 18,
                    color: colors.primary,
                  ),
                ),
                title: Text(
                  _reasonText(reason),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => Navigator.pop(context, reason),
              ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

Future<ReportContext?> showReportContextSheet(
  BuildContext context,
  ReportContext initial,
) => showModalBottomSheet<ReportContext>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ContextSheet(initial: initial),
);

class _ContextSheet extends StatefulWidget {
  const _ContextSheet({required this.initial});
  final ReportContext initial;

  @override
  State<_ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends State<_ContextSheet> {
  late ReportReason? reason = widget.initial.reason;
  late bool? ate = widget.initial.ateBefore;
  late bool? stress = widget.initial.stressed;
  late bool? fatigue = widget.initial.unusualFatigue;
  late bool? pain = widget.initial.pain;
  late bool? technique = widget.initial.techniqueChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session context',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optional factors that refine your workout insights.',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Why did you change the workout?
            Text(
              'Why did you change the workout?',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final value in ReportReason.values)
                  ChoiceChip(
                    avatar: Icon(
                      _reasonIcon(value),
                      size: 16,
                      color: reason == value
                          ? colors.onPrimary
                          : colors.primary,
                    ),
                    label: Text(_reasonText(value)),
                    selected: reason == value,
                    onSelected: (selected) =>
                        setState(() => reason = selected ? value : null),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Question items
            _answerCard(
              context,
              icon: Icons.restaurant_outlined,
              label: 'Did you eat before training?',
              value: ate,
              assign: (v) => ate = v,
            ),
            _answerCard(
              context,
              icon: Icons.psychology_outlined,
              label: 'Unusual stress before training?',
              value: stress,
              assign: (v) => stress = v,
            ),
            _answerCard(
              context,
              icon: Icons.battery_alert_outlined,
              label: 'Unusual fatigue before training?',
              value: fatigue,
              assign: (v) => fatigue = v,
            ),
            _answerCard(
              context,
              icon: Icons.healing_outlined,
              label: 'Did a movement cause pain?',
              value: pain,
              assign: (v) => pain = v,
            ),
            _answerCard(
              context,
              icon: Icons.fitness_center_outlined,
              label: 'Did technique or range of motion change?',
              value: technique,
              assign: (v) => technique = v,
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  ReportContext(
                    reason: reason,
                    ateBefore: ate,
                    stressed: stress,
                    unusualFatigue: fatigue,
                    pain: pain,
                    techniqueChanged: technique,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Update report',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _answerCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool? value,
    required void Function(bool?) assign,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final item in <(String, bool?)>[
                ('Unknown', null),
                ('Yes', true),
                ('No', false),
              ])
                ChoiceChip(
                  label: Text(item.$1),
                  selected: value == item.$2,
                  onSelected: (_) => setState(() => assign(item.$2)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _reasonIcon(ReportReason r) => switch (r) {
  ReportReason.time => Icons.schedule_rounded,
  ReportReason.fatigue => Icons.battery_alert_rounded,
  ReportReason.pain => Icons.healing_rounded,
  ReportReason.equipment => Icons.fitness_center_rounded,
  ReportReason.preference => Icons.thumb_up_alt_outlined,
};

String _reasonText(ReportReason r) => switch (r) {
  ReportReason.time => 'Time',
  ReportReason.fatigue => 'Fatigue',
  ReportReason.pain => 'Pain',
  ReportReason.equipment => 'Equipment',
  ReportReason.preference => 'Preference',
};
