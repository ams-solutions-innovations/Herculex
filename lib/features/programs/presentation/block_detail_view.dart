import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../workouts/presentation/workouts_providers.dart';
import '../domain/split_template.dart';
import 'programs_providers.dart';
import 'template_picker_sheet.dart';

/// Edit a block: per-week volume, the days in each week, their templates, and
/// the block's lifecycle (archive / delete).
///
/// Every structural edit re-materializes the schedule from today forward, so
/// completed and moved sessions in the past are never rewritten.
class BlockDetailView extends ConsumerWidget {
  const BlockDetailView({super.key, required this.programId});

  final int programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final programs = ref.watch(programsListProvider).value ?? const [];
    final program = programs.where((p) => p.id == programId).firstOrNull;
    final weeks = ref.watch(programWeeksProvider(programId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          program?.name ?? 'Block',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (program != null)
            PopupMenuButton<String>(
              onSelected: (value) => _menu(context, ref, program, value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'archive', child: Text('Archive block')),
                PopupMenuItem(value: 'delete', child: Text('Delete block')),
              ],
            ),
        ],
      ),
      body: program == null
          ? const Center(child: CircularProgressIndicator())
          : weeks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load weeks.\n$e')),
              data: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                children: [
                  _Summary(program: program),
                  const SizedBox(height: 20),
                  for (final week in list)
                    _WeekCard(program: program, week: week),
                ],
              ),
            ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    ProgramData program,
    String action,
  ) async {
    final repo = ref.read(programsRepositoryProvider);
    final navigator = Navigator.of(context);

    if (action == 'archive') {
      await repo.archiveProgram(program.id);
      navigator.pop();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this block?'),
        content: Text(
          'Every scheduled session in "${program.name}" is removed, including '
          'completed ones. Your workout history and templates are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.deleteProgram(program.id);
    navigator.pop();
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.program});

  final ProgramData program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = SplitType.fromId(program.splitType);
    final mode = ScheduleMode.fromId(program.scheduleMode);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final item in [
            (label: 'Split', value: split.label),
            (
              label: 'Schedule',
              value: mode == ScheduleMode.cycle
                  ? '${program.cycleLength ?? 7}-day cycle'
                  : '${program.daysPerWeek ?? '—'}× / week',
            ),
            (label: 'Length', value: '${program.weeks} weeks'),
          ])
            Expanded(
              child: Column(
                children: [
                  Text(
                    item.value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekCard extends ConsumerStatefulWidget {
  const _WeekCard({required this.program, required this.week});

  final ProgramData program;
  final ProgramWeekData week;

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
    final isDeload = volume < 0.95;

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
                for (final day in list) _DayRow(program: widget.program, day: day),
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

class _DayRow extends ConsumerWidget {
  const _DayRow({required this.program, required this.day});

  final ProgramData program;
  final ProgramDayData day;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templates = ref.watch(workoutTemplateByIdProvider(day.templateId));
    final slot = day.cycleDayIndex != null
        ? 'Day ${day.cycleDayIndex! + 1}'
        : _weekdays[(day.dayOfWeek - 1).clamp(0, 6)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              slot,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.slotLabel?.isNotEmpty == true ? day.slotLabel! : day.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  templates == null
                      ? 'No template — sessions will be empty'
                      : templates.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: templates == null
                        ? AppColors.tertiary
                        : AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Link a template',
            icon: Icon(
              day.templateId == null
                  ? Icons.link_rounded
                  : Icons.swap_horiz_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            onPressed: () => _link(context, ref),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove this day',
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              size: 20,
              color: AppColors.secondary,
            ),
            onPressed: () => _remove(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final picked = await TemplatePickerSheet.show(context);
    if (picked == null) return;
    final repo = ref.read(programsRepositoryProvider);
    await repo.setProgramDayTemplate(day.id, picked.id);
    await repo.rematerializeProgram(program.id);
  }

  Future<void> _remove(WidgetRef ref) async {
    final repo = ref.read(programsRepositoryProvider);
    await repo.deleteProgramDay(day.id);
    await repo.rematerializeProgram(program.id);
  }
}

/// One template by id, or null — used to label a program day's link.
/// `-1` is TemplatesRepository's "every folder" sentinel.
final workoutTemplateByIdProvider = Provider.family<WorkoutTemplateData?, int?>((
  ref,
  id,
) {
  if (id == null) return null;
  final all = ref.watch(workoutTemplatesProvider(-1)).value;
  return all?.where((t) => t.id == id).firstOrNull;
});
