import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/app_bottom_sheet.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/sheets/exercise_replacement_sheet.dart';
import 'package:herculex/features/programs/presentation/sheets/template_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/widgets/program_muscle_volume_card.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

part 'block_detail_view/_week_card.part.dart';
part 'block_detail_view/_day_row.part.dart';

/// Edit a block: the Week/Wave editor. A Week dropdown selects one active
/// week at a time (D-01); directly beneath it, a wave-strip label explains
/// which rotation wave the viewed week belongs to (D-05). Per-exercise and
/// day-level replacement/link triggers reach a scoped rotation write plus
/// [ProgramsRepository.rematerializeProgram] (D-04), never disturbing
/// already-started or completed sessions.
class BlockDetailView extends ConsumerStatefulWidget {
  const BlockDetailView({super.key, required this.programId});

  final int programId;

  @override
  ConsumerState<BlockDetailView> createState() => _BlockDetailViewState();
}

class _BlockDetailViewState extends ConsumerState<BlockDetailView> {
  int _selectedWeekIndex = 0;

  @override
  Widget build(BuildContext context) {
    final programs = ref.watch(programsListProvider).value ?? const [];
    final program = programs.where((p) => p.id == widget.programId).firstOrNull;
    final weeks = ref.watch(programWeeksProvider(widget.programId));
    final volumeAsync = ref.watch(
      programVolumeBreakdownProvider(widget.programId),
    );
    final tracking = ref.watch(programTrackingProvider(widget.programId));

    return HxScreenShell(
      title: program?.name ?? 'Block',
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
      children: [
        if (program == null)
          const Center(child: CircularProgressIndicator())
        else
          weeks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load weeks.\n$e')),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final selectedWeek = list.firstWhere(
                (week) => week.weekIndex == _selectedWeekIndex,
                orElse: () => list.first,
              );
              return Column(
                children: [
                  _Summary(program: program),
                  const SizedBox(height: 16),
                  tracking.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (snapshot) => _ProgramTrackingCard(
                      snapshot: snapshot,
                      totalWeeks: program.weeks,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (volumeAsync.value != null &&
                      volumeAsync.value!.isNotEmpty)
                    ProgramMuscleVolumeCard(
                      breakdown: volumeAsync.value!,
                      title: 'Weekly Volume per Muscle Group',
                    ),
                  const SizedBox(height: 4),
                  _WeekDropdown(
                    weekCount: list.length,
                    selectedWeekIndex: selectedWeek.weekIndex,
                    onChanged: (value) =>
                        setState(() => _selectedWeekIndex = value ?? 0),
                  ),
                  const SizedBox(height: 8),
                  _WaveStrip(
                    programId: program.id,
                    programWeekId: selectedWeek.id,
                    weekIndex: selectedWeek.weekIndex,
                    totalWeeks: list.length,
                  ),
                  const SizedBox(height: 12),
                  _WeekCard(
                    program: program,
                    week: selectedWeek,
                    totalWeeks: list.length,
                  ),
                ],
              );
            },
          ),
      ],
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

class _ProgramTrackingCard extends StatelessWidget {
  const _ProgramTrackingCard({
    required this.snapshot,
    required this.totalWeeks,
  });

  final ProgramTrackingSnapshot snapshot;
  final int totalWeeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = snapshot.completedSessions;
    final planned = snapshot.plannedSessions;
    final phase = snapshot.phase == null
        ? null
        : snapshot.phase![0].toUpperCase() + snapshot.phase!.substring(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: .3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Program progress',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completed / $planned sessions',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: snapshot.adherence,
              minHeight: 7,
              backgroundColor: AppColors.outlineVariant.withValues(alpha: .25),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('Wave', '${snapshot.currentWeekIndex + 1}/$totalWeeks'),
              if (phase != null) _metric('Phase', phase),
              _metric('Quality sets', '${snapshot.qualitySets}'),
              if (snapshot.maxEffortTopSets > 0)
                _metric('ME top sets', '${snapshot.maxEffortTopSets}'),
              if (snapshot.skippedSessions > 0)
                _metric('Skipped', '${snapshot.skippedSessions}'),
            ],
          ),
          if (snapshot.nextRotation != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.sync_rounded, size: 17, color: AppColors.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Next rotation: ${snapshot.nextRotation}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (snapshot.exercisePrs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'BEST ESTIMATED 1RM',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 6),
            for (final lift in snapshot.exercisePrs)
              _progressRow(theme, lift.label, lift.e1RmKg),
          ],
          if (snapshot.movementFamilyTrends.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'MOVEMENT-FAMILY TREND',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 6),
            for (final trend in snapshot.movementFamilyTrends)
              _progressRow(theme, trend.label, trend.e1RmKg),
          ],
        ],
      ),
    );
  }

  static Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label · $value'),
    );
  }

  static Widget _progressRow(ThemeData theme, String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.replaceAll('_', ' '),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            '${value.round()} kg',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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

/// The Week dropdown (D-01): "Week N of M" — never a scrollable stack of
/// every week's card. Selecting a value drives which single active week
/// [_WeekCard] and [_WaveStrip] render.
class _WeekDropdown extends StatelessWidget {
  const _WeekDropdown({
    required this.weekCount,
    required this.selectedWeekIndex,
    required this.onChanged,
  });

  final int weekCount;
  final int selectedWeekIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.outlineVariant.withValues(alpha: .35),
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedWeekIndex,
        isExpanded: true,
        dropdownColor: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        onChanged: onChanged,
        items: [
          for (var i = 0; i < weekCount; i++)
            DropdownMenuItem(
              value: i,
              child: Text('Week ${i + 1} of $weekCount'),
            ),
        ],
      ),
    ),
  );
}

/// D-05's "Exercise wave X of Y · Weeks A–B" indicator, always a distinct
/// [Text] widget from [_WeekDropdown]'s own label — never string-concatenated
/// into one line. Renders nothing while loading or when the viewed week has
/// no anchor `main` slot.
class _WaveStrip extends ConsumerWidget {
  const _WaveStrip({
    required this.programId,
    required this.programWeekId,
    required this.weekIndex,
    required this.totalWeeks,
  });

  final int programId;
  final int programWeekId;
  final int weekIndex;
  final int totalWeeks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(
      waveLabelProvider((
        programId: programId,
        programWeekId: programWeekId,
        weekIndex: weekIndex,
        totalWeeks: totalWeeks,
      )),
    );
    final label = info.value?.label;
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.secondary),
      ),
    );
  }
}

/// One template by id, or null — used to label a program day's link.
/// `-1` is TemplatesRepository's "every folder" sentinel.
final workoutTemplateByIdProvider = Provider.family<WorkoutTemplateData?, int?>(
  (ref, id) {
    if (id == null) return null;
    final all = ref.watch(workoutTemplatesProvider(-1)).value;
    return all?.where((t) => t.id == id).firstOrNull;
  },
);
