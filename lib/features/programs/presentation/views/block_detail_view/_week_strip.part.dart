part of '../block_detail_view.dart';

/// Horizontal W1…Wn chips (D-01): one active week at a time, with the week
/// the user is in marked and the finished ones ticked.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weeks,
    required this.selectedWeekIndex,
    required this.currentWeekIndex,
    required this.onChanged,
  });

  final List<ProgramWeekData> weeks;
  final int selectedWeekIndex;
  final int? currentWeekIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: weeks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final week = weeks[i];
          final selected = week.weekIndex == selectedWeekIndex;
          final current = week.weekIndex == currentWeekIndex;
          final done =
              currentWeekIndex != null && week.weekIndex < currentWeekIndex!;
          return InkWell(
            borderRadius: HxRadius.pillAll,
            onTap: () {
              Haptics.selection();
              onChanged(week.weekIndex);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? hx.primary : hx.surfaceContainer,
                borderRadius: HxRadius.pillAll,
                border: Border.all(
                  color: current && !selected
                      ? hx.primary
                      : hx.outlineVariant.withValues(alpha: 0.35),
                  width: current && !selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (done) ...[
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: selected ? hx.onPrimary : hx.success,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    'W${week.weekIndex + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? hx.onPrimary : hx.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
