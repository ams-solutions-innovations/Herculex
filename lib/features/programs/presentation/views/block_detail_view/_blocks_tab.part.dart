part of '../block_detail_view.dart';

/// The program at block level: consecutive weeks grouped by phase, each with
/// the sessions and exercises of its first week. Tapping a week chip opens
/// that week in the Weeks tab for editing.
class _BlocksTab extends StatelessWidget {
  const _BlocksTab({
    required this.program,
    required this.weeks,
    required this.currentWeekIndex,
    required this.onOpenWeek,
  });

  final ProgramData program;
  final List<ProgramWeekData> weeks;
  final int? currentWeekIndex;
  final ValueChanged<int> onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final model = PeriodizationModel.fromId(program.periodizationModel);
    final blocks = groupWeeksIntoBlocks([
      for (final week in weeks)
        (
          weekIndex: week.weekIndex,
          phase: week.blockPhase,
          isDeload: Periodization.isPlannedDeload(
            model: model,
            totalWeeks: program.weeks,
            weekIndex: week.weekIndex,
          ),
        ),
    ]);
    final weekByIndex = {for (final week in weeks) week.weekIndex: week};

    return Column(
      children: [
        for (final (i, block) in blocks.indexed)
          _BlockCard(
            number: i + 1,
            block: block,
            firstWeek: weekByIndex[block.firstWeek]!,
            currentWeekIndex: currentWeekIndex,
            onOpenWeek: onOpenWeek,
          ),
      ],
    );
  }
}

class _BlockCard extends ConsumerWidget {
  const _BlockCard({
    required this.number,
    required this.block,
    required this.firstWeek,
    required this.currentWeekIndex,
    required this.onOpenWeek,
  });

  final int number;
  final WeekBlock block;
  final ProgramWeekData firstWeek;
  final int? currentWeekIndex;
  final ValueChanged<int> onOpenWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final days = ref.watch(programDaysProvider(firstWeek.id)).value ?? const [];
    final current = block.weekIndices.contains(currentWeekIndex);
    final finished =
        currentWeekIndex != null && block.lastWeek < currentWeekIndex!;
    final accent = block.isDeload ? hx.tertiary : hx.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HxCard(
        accent: current ? accent : null,
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
                        'Block $number · ${block.label}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        block.weeksLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: hx.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (current)
                  HxTextPill(label: 'Now', selected: true, accent: accent)
                else if (finished)
                  Icon(Icons.check_circle_rounded, color: hx.success, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final weekIndex in block.weekIndices)
                  HxTextPill(
                    label: 'W${weekIndex + 1}',
                    selected: weekIndex == currentWeekIndex,
                    onTap: () => onOpenWeek(weekIndex),
                  ),
              ],
            ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final day in days.where((day) => !day.isRest))
                _BlockDayPreview(day: day),
            ],
          ],
        ),
      ),
    );
  }
}

/// A session of the block in one line: its name and a row of exercise
/// pictures.
class _BlockDayPreview extends ConsumerWidget {
  const _BlockDayPreview({required this.day});

  final ProgramDayData day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final items =
        ref.watch(programDayExerciseSummariesProvider(day.id)).value ??
        const <ProgramDayExerciseSummary>[];
    final template = ref.watch(workoutTemplateByIdProvider(day.templateId));
    final name = day.slotLabel?.isNotEmpty == true ? day.slotLabel! : day.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template == null ? name : '$name · ${template.name}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final exercise = items[i].exercise;
                  return Tooltip(
                    message: items[i].name,
                    child: exercise == null
                        ? const ExerciseArtwork.fromSlug(
                            slug: null,
                            size: 36,
                            radius: 9,
                          )
                        : ExerciseArtwork(
                            exercise: exercise,
                            size: 36,
                            radius: 9,
                          ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              items.map((item) => item.name).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: hx.secondary),
            ),
          ],
        ],
      ),
    );
  }
}
