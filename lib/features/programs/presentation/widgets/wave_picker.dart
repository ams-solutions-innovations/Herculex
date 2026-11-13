import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';

/// Chooses which exercise wave of a block to review, e.g. "Wave 2 · Weeks 4–6".
///
/// A wave is a run of weeks in which no exercise is swapped, so this replaces a
/// week-by-week picker for blocks whose exercises rotate. The wave holding
/// [selectedWeekIndex] is highlighted.
class WavePicker extends StatelessWidget {
  const WavePicker({
    super.key,
    required this.waves,
    required this.selectedWeekIndex,
    required this.onSelected,
  });

  final List<WaveSegment> waves;
  final int selectedWeekIndex;
  final ValueChanged<WaveSegment> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final wave in waves)
          ChoiceChip(
            key: ValueKey('wave-chip-${wave.index}'),
            selected: wave.contains(selectedWeekIndex),
            onSelected: (_) => onSelected(wave),
            showCheckmark: false,
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Wave ${wave.index}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  wave.weeksLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
