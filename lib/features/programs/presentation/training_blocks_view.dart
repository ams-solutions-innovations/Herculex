import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/glass_container.dart';
import '../../../widgets/premium_button.dart';
import '../domain/split_template.dart';
import 'block_builder_view.dart';
import 'block_detail_view.dart';
import 'day_detail_sheet.dart';
import 'program_marketplace_view.dart';
import 'programs_providers.dart';
import 'widgets/month_calendar.dart';
import 'widgets/week_board.dart';

class TrainingBlocksView extends ConsumerWidget {
  const TrainingBlocksView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProgram = ref.watch(activeProgramProvider);
    final mode = ref.watch(blocksViewModeProvider);
    final selected = ref.watch(selectedBlockDateProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: activeProgram.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load blocks.\n$e')),
          data: (program) {
            if (program == null) return const _NoBlockState();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                _BlockHeader(program: program),
                const SizedBox(height: 14),
                _ViewModeBar(mode: mode),
                const SizedBox(height: 14),
                _PeriodNavigator(program: program, mode: mode, date: selected),
                const SizedBox(height: 14),
                _ConflictBanner(program: program, mode: mode, date: selected),
                if (mode == BlocksViewMode.week)
                  WeekBoard(
                    anchor: selected,
                    programId: program.id,
                    onOpenDay: (date) => _openDay(context, ref, date, program),
                    onOpenSession: (row) =>
                        _openDay(context, ref, row.date, program),
                  )
                else
                  MonthCalendar(
                    anchor: selected,
                    programId: program.id,
                    selected: selected,
                    onSelect: (date) {
                      ref.read(selectedBlockDateProvider.notifier).state = date;
                      _openDay(context, ref, date, program);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openDay(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    ProgramData program,
  ) {
    DayDetailSheet.show(context, date: date, programId: program.id);
  }
}

// ── Header: which block, and how to switch ───────────────────────────────────

class _BlockHeader extends ConsumerWidget {
  const _BlockHeader({required this.program});

  final ProgramData program;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekOf = _currentWeek(ref);
    final split = SplitType.fromId(program.splitType);
    final mode = ScheduleMode.fromId(program.scheduleMode);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showSwitcher(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          program.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        color: AppColors.secondary,
                      ),
                    ],
                  ),
                  Text(
                    [
                      if (split != SplitType.custom) split.label,
                      if (mode == ScheduleMode.cycle)
                        '${program.cycleLength ?? 7}-day cycle',
                      if (weekOf != null)
                        'Week $weekOf of ${program.weeks}'
                      else
                        '${program.weeks} weeks',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Edit block',
          icon: Icon(Icons.tune_rounded, color: AppColors.onSurfaceVariant),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlockDetailView(programId: program.id),
            ),
          ),
        ),
        IconButton(
          tooltip: 'New block',
          icon: Icon(Icons.add_circle, color: AppColors.primary, size: 28),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BlockBuilderView()),
          ),
        ),
      ],
    );
  }

  /// Which week of the block today falls in, or null if it is outside.
  int? _currentWeek(WidgetRef ref) {
    final startIso = program.startDateIso;
    if (startIso == null) return null;
    final start = DateTime.parse(startIso);
    final now = ref.read(clockProvider).now();
    final days = DateTime(now.year, now.month, now.day).difference(start).inDays;
    if (days < 0) return null;
    final week = (days ~/ 7) + 1;
    return week > program.weeks ? null : week;
  }

  void _showSwitcher(BuildContext context, WidgetRef ref) {
    Haptics.selection();
    AppBottomSheet.show(
      context,
      builder: (_) => const _BlockSwitcherSheet(),
    );
  }
}

class _BlockSwitcherSheet extends ConsumerWidget {
  const _BlockSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final programs = ref.watch(programsListProvider);

    return AppBottomSheet(
      title: 'Your blocks',
      subtitle: 'Pick the block the tab follows',
      initialSize: 0.55,
      child: programs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Could not load blocks.', style: theme.textTheme.bodyMedium),
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    await ref
                        .read(programsRepositoryProvider)
                        .setActiveProgram(p.id);
                    navigator.pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: p.isActive
                            ? AppColors.primary
                            : AppColors.outlineVariant.withValues(alpha: 0.4),
                        width: p.isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${SplitType.fromId(p.splitType).label} · '
                                '${p.weeks} weeks',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (p.isActive)
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            PremiumButton(
              text: 'Build a new block',
              icon: Icons.add_rounded,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockBuilderView()),
                );
              },
            ),
            const SizedBox(height: 8),
            PremiumButton(
              text: 'Browse programs',
              icon: Icons.search_rounded,
              isPrimary: false,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProgramMarketplaceView(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Week | Month ─────────────────────────────────────────────────────────────

class _ViewModeBar extends ConsumerWidget {
  const _ViewModeBar({required this.mode});

  final BlocksViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final option in BlocksViewMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Haptics.selection();
                  ref.read(blocksViewModeProvider.notifier).set(option);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: mode == option
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text(
                      option == BlocksViewMode.week ? 'Week' : 'Month',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: mode == option
                            ? Colors.white
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Steps through weeks or months and shows the phase of the week in view.
class _PeriodNavigator extends ConsumerWidget {
  const _PeriodNavigator({
    required this.program,
    required this.mode,
    required this.date,
  });

  final ProgramData program;
  final BlocksViewMode mode;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final label = mode == BlocksViewMode.week
        ? _weekLabel()
        : DateFormat('MMMM yyyy').format(date);

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _step(ref, -1),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (mode == BlocksViewMode.week) _PhaseChip(program: program, date: date),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _step(ref, 1),
        ),
      ],
    );
  }

  String _weekLabel() {
    final monday = WeekBoard.mondayOf(date);
    final sunday = monday.add(const Duration(days: 6));
    final sameMonth = monday.month == sunday.month;
    return sameMonth
        ? '${DateFormat('MMM d').format(monday)} – ${sunday.day}'
        : '${DateFormat('MMM d').format(monday)} – '
              '${DateFormat('MMM d').format(sunday)}';
  }

  void _step(WidgetRef ref, int direction) {
    Haptics.light();
    final notifier = ref.read(selectedBlockDateProvider.notifier);
    notifier.state = mode == BlocksViewMode.week
        ? date.add(Duration(days: 7 * direction))
        : DateTime(date.year, date.month + direction, 1);
  }
}

/// The real periodization phase of the week in view, from `ProgramWeeks` —
/// replacing the label that used to be hardcoded to "week 4 = deload".
class _PhaseChip extends ConsumerWidget {
  const _PhaseChip({required this.program, required this.date});

  final ProgramData program;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startIso = program.startDateIso;
    if (startIso == null) return const SizedBox.shrink();
    final weeks = ref.watch(programWeeksProvider(program.id)).value;
    if (weeks == null || weeks.isEmpty) return const SizedBox.shrink();

    final start = DateTime.parse(startIso);
    final index = WeekBoard.mondayOf(date)
            .difference(WeekBoard.mondayOf(start))
            .inDays ~/
        7;
    if (index < 0 || index >= weeks.length) return const SizedBox.shrink();
    final week = weeks[index];

    final isDeload = week.adjustmentFactor < 0.95;
    final label = isDeload
        ? 'Deload'
        : switch (week.blockPhase) {
            'accumulation' => 'Accumulation',
            'transmutation' => 'Transmutation',
            'realization' => 'Realization',
            _ => 'Week ${week.weekIndex + 1}',
          };
    final volume = (week.adjustmentFactor * 100).round();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label · $volume% volume',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isDeload ? AppColors.tertiary : AppColors.secondary,
        ),
      ),
    );
  }
}

/// Fatigue conflicts in the window on screen. Unlike the old banner, the fix
/// button actually moves the offending session.
class _ConflictBanner extends ConsumerWidget {
  const _ConflictBanner({
    required this.program,
    required this.mode,
    required this.date,
  });

  final ProgramData program;
  final BlocksViewMode mode;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = mode == BlocksViewMode.week
        ? ScheduleRange.week(date, programId: program.id)
        : ScheduleRange.monthGrid(date, programId: program.id);
    final conflicts = ref.watch(recoveryConflictsProvider(range)).value;
    if (conflicts == null || conflicts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final first = conflicts.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        color: AppColors.tertiary.withValues(alpha: 0.12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                Text(
                  conflicts.length == 1
                      ? 'Recovery conflict'
                      : '${conflicts.length} recovery conflicts',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(first['message'] as String, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            PremiumButton(
              text: 'Push the second session out a day',
              isPrimary: false,
              onTap: () async {
                final repo = ref.read(programsRepositoryProvider);
                final id = first['scheduledWorkoutId2'] as int;
                final current = DateTime.parse(first['dateIso'] as String);
                await repo.moveScheduledWorkout(
                  scheduleId: id,
                  newDate: current.add(const Duration(days: 1)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── No active block ──────────────────────────────────────────────────────────

class _NoBlockState extends ConsumerWidget {
  const _NoBlockState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(programsListProvider).value ?? const <ProgramData>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
      children: [
        Text(
          'Training Blocks',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 32),
        GlassContainer(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 44,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                all.isEmpty ? 'No training block yet' : 'No active block',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                all.isEmpty
                    ? 'Pick a split — upper/lower, push-pull-legs, full body, '
                          'A/B, a bro split or your own — and attach your '
                          'templates to each day.'
                    : 'Choose which of your blocks the tab should follow.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 22),
              if (all.isEmpty)
                PremiumButton(
                  text: 'Build a block',
                  icon: Icons.add_rounded,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BlockBuilderView()),
                  ),
                )
              else
                for (final p in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumButton(
                      text: p.name,
                      isPrimary: false,
                      onTap: () => ref
                          .read(programsRepositoryProvider)
                          .setActiveProgram(p.id),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PremiumButton(
          text: 'Browse programs',
          icon: Icons.search_rounded,
          isPrimary: false,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProgramMarketplaceView()),
          ),
        ),
      ],
    );
  }
}
