/// One week as the block overview sees it.
typedef WeekPhase = ({int weekIndex, String? phase, bool isDeload});

/// A run of consecutive weeks that share a training phase. A planned deload
/// week always stands on its own, so a block reads "accumulation, deload,
/// intensification…" rather than one long undifferentiated list.
class WeekBlock {
  const WeekBlock({
    required this.phase,
    required this.isDeload,
    required this.weekIndices,
  });

  /// Raw phase id (`accumulation`, …) or null for a plain week.
  final String? phase;
  final bool isDeload;
  final List<int> weekIndices;

  int get firstWeek => weekIndices.first;
  int get lastWeek => weekIndices.last;

  String get label {
    if (isDeload) return 'Deload';
    return switch (phase) {
      'accumulation' => 'Accumulation',
      'transmutation' => 'Transmutation',
      'realization' => 'Realization',
      _ => 'Training',
    };
  }

  /// "Week 3" or "Weeks 1–4", 1-based.
  String get weeksLabel => firstWeek == lastWeek
      ? 'Week ${firstWeek + 1}'
      : 'Weeks ${firstWeek + 1}–${lastWeek + 1}';
}

/// Groups [weeks] (in any order) into consecutive [WeekBlock]s.
List<WeekBlock> groupWeeksIntoBlocks(Iterable<WeekPhase> weeks) {
  final sorted = weeks.toList()
    ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  final blocks = <WeekBlock>[];
  for (final week in sorted) {
    final last = blocks.lastOrNull;
    final continues =
        last != null &&
        !week.isDeload &&
        !last.isDeload &&
        last.phase == week.phase &&
        last.lastWeek == week.weekIndex - 1;
    if (continues) {
      blocks[blocks.length - 1] = WeekBlock(
        phase: last.phase,
        isDeload: false,
        weekIndices: [...last.weekIndices, week.weekIndex],
      );
    } else {
      blocks.add(
        WeekBlock(
          phase: week.phase,
          isDeload: week.isDeload,
          weekIndices: [week.weekIndex],
        ),
      );
    }
  }
  return blocks;
}
