import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/nutrition/domain/log_dates.dart';

/// "Repeat for several weeks" switch under the multi-day picker.
///
/// When on, the chosen days (and the entry's own day) are written again for
/// each following week; [weeks] says how many weeks in total.
class RepeatWeeksToggle extends StatelessWidget {
  const RepeatWeeksToggle({
    super.key,
    required this.enabled,
    required this.weeks,
    required this.onEnabledChanged,
    required this.onWeeksChanged,
  });

  final bool enabled;
  final int weeks;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onWeeksChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repeat for multiple weeks',
                    style: TextStyle(color: AppColors.onSurface, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Same days, every week for $weeks weeks'
                        : 'Only this week',
                    style: TextStyle(color: AppColors.secondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onEnabledChanged,
              activeTrackColor: AppColors.primary,
              activeThumbColor: Colors.white,
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in kRepeatWeekOptions)
                HxTextPill(
                  label: '$option weeks',
                  selected: option == weeks,
                  onTap: () => onWeeksChanged(option),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
