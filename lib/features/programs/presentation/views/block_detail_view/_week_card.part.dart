part of '../block_detail_view.dart';

/// One active week's body: phase/deload badge, intensity, the volume slider,
/// and the day list (each day rendered by [_DayRow]). Exactly one instance
/// is ever mounted at a time — the caller in [_BlockDetailViewState] selects
/// which week via the Week dropdown (D-01).
class _WeekCard extends ConsumerStatefulWidget {
  const _WeekCard({
    required this.program,
    required this.week,
    required this.totalWeeks,
  });

  final ProgramData program;
  final ProgramWeekData week;
  final int totalWeeks;

  @override
  ConsumerState<_WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends ConsumerState<_WeekCard> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = ref.watch(programDaysProvider(widget.week.id));
    final volume = _draft ?? widget.week.adjustmentFactor;
    final isDeload = Periodization.isPlannedDeload(
      model: PeriodizationModel.fromId(widget.program.periodizationModel),
      totalWeeks: widget.program.weeks,
      weekIndex: widget.week.weekIndex,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Week ${widget.week.weekIndex + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isDeload ? AppColors.tertiary : AppColors.primary)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isDeload ? 'Deload' : _phaseLabel(widget.week.blockPhase),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDeload ? AppColors.tertiary : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Intensity ${(widget.week.intensityFactor * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          Row(
            children: [
              Text(
                'VOLUME',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1,
                ),
              ),
              Expanded(
                child: Slider(
                  value: volume.clamp(0.6, 1.2),
                  min: 0.6,
                  max: 1.2,
                  divisions: 12,
                  label: '${(volume * 100).round()}%',
                  onChanged: (v) => setState(() => _draft = v),
                  // Written on release, not per pixel.
                  onChangeEnd: (v) async {
                    Haptics.light();
                    await ref
                        .read(programsRepositoryProvider)
                        .setWeekAdjustment(widget.week.id, adjustmentFactor: v);
                    if (mounted) setState(() => _draft = null);
                  },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(volume * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          days.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) => Column(
              children: [
                for (final day in list)
                  _DayRow(
                    program: widget.program,
                    day: day,
                    week: widget.week,
                    totalWeeks: widget.totalWeeks,
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _addDay(list),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add a day'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _phaseLabel(String? phase) => switch (phase) {
    'accumulation' => 'Accumulation',
    'transmutation' => 'Transmutation',
    'realization' => 'Realization',
    _ => 'Standard',
  };

  Future<void> _addDay(List<ProgramDayData> existing) async {
    final isCycle =
        ScheduleMode.fromId(widget.program.scheduleMode) == ScheduleMode.cycle;
    final slot = await _pickSlot(isCycle);
    if (slot == null || !mounted) return;

    final repo = ref.read(programsRepositoryProvider);
    await repo.addProgramDay(
      programWeekId: widget.week.id,
      dayOfWeek: isCycle ? 1 : slot,
      cycleDayIndex: isCycle ? slot : null,
      name: 'New session',
      slotLabel: 'New session',
    );
    await repo.rematerializeProgram(widget.program.id);
  }

  Future<int?> _pickSlot(bool isCycle) {
    final length = isCycle ? (widget.program.cycleLength ?? 7) : 7;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AppBottomSheet(
        scrollable: false,
        title: isCycle ? 'Which cycle day?' : 'Which weekday?',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < length; i++)
              ActionChip(
                label: Text(
                  isCycle
                      ? 'Day ${i + 1}'
                      : const [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun',
                        ][i],
                ),
                onPressed: () => Navigator.pop(context, isCycle ? i : i + 1),
              ),
          ],
        ),
      ),
    );
  }
}
