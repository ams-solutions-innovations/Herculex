import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/app_bottom_sheet.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';

/// Bottom sheet that picks which week of a block to look at, either one week
/// at a time or by exercise wave ("Wave 1 (Weeks 1–3)"). Resolves to a 0-based
/// week index — a wave resolves to its first week, since every week in a wave
/// carries the same exercises.
Future<int?> showWeekWavePickerSheet(
  BuildContext context, {
  required List<int> weekIndices,
  required int selectedWeekIndex,
  List<WaveRange> waves = const [],
}) => AppBottomSheet.show<int>(
  context,
  builder: (_) => WeekWavePickerSheet(
    weekIndices: weekIndices,
    selectedWeekIndex: selectedWeekIndex,
    waves: waves,
  ),
);

class WeekWavePickerSheet extends StatefulWidget {
  const WeekWavePickerSheet({
    super.key,
    required this.weekIndices,
    required this.selectedWeekIndex,
    this.waves = const [],
  });

  final List<int> weekIndices;
  final int selectedWeekIndex;
  final List<WaveRange> waves;

  @override
  State<WeekWavePickerSheet> createState() => _WeekWavePickerSheetState();
}

class _WeekWavePickerSheetState extends State<WeekWavePickerSheet> {
  bool _byWave = false;

  @override
  Widget build(BuildContext context) {
    final hasWaves = widget.waves.isNotEmpty;
    return AppBottomSheet(
      scrollable: false,
      title: _byWave ? 'Choose a wave' : 'Choose a week',
      subtitle: _byWave
          ? 'Exercises stay the same for every week inside a wave.'
          : null,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasWaves) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('By week')),
                ButtonSegment(value: true, label: Text('By wave')),
              ],
              selected: {_byWave},
              onSelectionChanged: (value) {
                Haptics.selection();
                setState(() => _byWave = value.first);
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_byWave)
            for (var i = 0; i < widget.waves.length; i++)
              _OptionTile(
                title: 'Wave ${i + 1}',
                detail: '(${widget.waves[i].weeksLabel})',
                selected: widget.waves[i].contains(widget.selectedWeekIndex),
                onTap: () => Navigator.pop(context, widget.waves[i].startWeek),
              )
          else
            for (final weekIndex in widget.weekIndices)
              _OptionTile(
                title: 'Week ${weekIndex + 1}',
                detail: 'of ${widget.weekIndices.length}',
                selected: weekIndex == widget.selectedWeekIndex,
                onTap: () => Navigator.pop(context, weekIndex),
              ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: .14)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
