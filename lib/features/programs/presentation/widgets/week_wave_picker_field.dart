import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';
import 'package:herculex/features/programs/presentation/sheets/week_wave_picker_sheet.dart';

/// The tappable "Week 3 of 12" row that replaces the old week dropdown. It
/// opens [showWeekWavePickerSheet] from the bottom of the screen.
class WeekWavePickerField extends StatelessWidget {
  const WeekWavePickerField({
    super.key,
    required this.weekIndices,
    required this.selectedWeekIndex,
    required this.onChanged,
    this.waves = const [],
  });

  final List<int> weekIndices;
  final int selectedWeekIndex;
  final ValueChanged<int> onChanged;
  final List<WaveRange> waves;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waveIndex = waves.indexWhere((w) => w.contains(selectedWeekIndex));
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final picked = await showWeekWavePickerSheet(
            context,
            weekIndices: weekIndices,
            selectedWeekIndex: selectedWeekIndex,
            waves: waves,
          );
          if (picked != null && picked != selectedWeekIndex) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: .35),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Week ${selectedWeekIndex + 1} of ${weekIndices.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (waveIndex >= 0)
                      Text(
                        'Wave ${waveIndex + 1} (${waves[waveIndex].weeksLabel})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_up_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
