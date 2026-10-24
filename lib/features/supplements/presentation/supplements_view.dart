import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_habit_stats.dart';
import 'package:herculex/features/supplements/presentation/supplement_database_sheet.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';
import 'package:herculex/features/supplements/presentation/supplement_scan_flow.dart';
import 'package:intl/intl.dart';

const _accent = Color(0xFF9B59B6);
const _perfectGreen = Color(0xFF2ECC71);

/// Shared by the two half-width actions under the scan button, so the pair
/// matches and the labels fit beside each other on a phone.
final _secondaryActionStyle = OutlinedButton.styleFrom(
  foregroundColor: _accent,
  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(horizontal: HxSpace.x3, vertical: 14),
);

/// Full supplements page: interactive day checklist, 7-day habit strip,
/// unified barcode/DB/AI scanner, and comprehensive habit-tracking analytics
/// (streaks, consistency charts, 28-day heatmap, and per-supplement adherence).
class SupplementsView extends ConsumerWidget {
  const SupplementsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(supplementSelectedDayStateProvider);
    final habitStats = ref.watch(supplementHabitStatsProvider);
    final selectedDate = ref.watch(supplementSelectedDateProvider);

    return HxScreenShell(
      title: 'Supplements',
      titleIcon: Icons.medication_outlined,
      children: [
        stateAsync.when(
          data: (state) => _Body(
            state: state,
            habitStats: habitStats,
            selectedDate: selectedDate,
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(HxSpace.x6),
            child: Text(
              'Failed to load supplements: $e',
              style: TextStyle(color: context.hx.danger),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openDatabasePicker(BuildContext context) async {
  final resolved = await SupplementDatabaseSheet.show(context);
  if (resolved != null && context.mounted) {
    await SupplementEditSheet.show(
      context,
      existing: resolved.supplement,
      isNewDraft: true,
      initialScanMessage:
          '${resolved.sourceLabel} · "${resolved.supplement.name}"',
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _Body extends ConsumerWidget {
  const _Body({
    required this.state,
    required this.habitStats,
    required this.selectedDate,
  });

  final SupplementDayState state;
  final SupplementHabitStats habitStats;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _isSameDay(selectedDate, today);

    final itemStatsById = {
      for (final s in habitStats.itemStats) s.supplement.id: s,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Day Progress + 7-Day Interactive Strip ────────────────────────
        _DayHeaderCard(
          state: state,
          habitStats: habitStats,
          selectedDate: selectedDate,
          today: today,
        ),
        const SizedBox(height: HxSpace.x4),

        // ── Unified Scan + Supplement Database + Manual Add Actions ───────
        FilledButton.icon(
          onPressed: () => scanAndAddSupplement(context, ref),
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text('Scan (Code / AI)'),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openDatabasePicker(context),
                icon: const Icon(Icons.library_books_outlined, size: 18),
                label: const Text('Supplement DB'),
                style: _secondaryActionStyle,
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => SupplementEditSheet.show(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Manually'),
                style: _secondaryActionStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x4),

        // ── Daily Checklist ───────────────────────────────────────────────
        if (state.supplements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
            child: Center(
              child: Text(
                'Scan a barcode (falls back to AI label analysis if not in the database) or pick a supplement from the database.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          )
        else ...[
          for (final s in state.supplements) ...[
            _Row(
              supplement: s,
              isTaken: state.isTaken(s.id),
              selectedDate: selectedDate,
              isToday: isToday,
              itemStat: itemStatsById[s.id],
            ),
            const SizedBox(height: HxSpace.x2),
          ],
          Padding(
            padding: const EdgeInsets.only(top: HxSpace.x1),
            child: Text(
              'Tap to toggle dose · long-press or tap the pencil icon to edit.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: HxSpace.x6),

          // ── Habit Tracking & Consistency Analytics ──────────────────────
          _HabitAnalyticsSection(
            stats: habitStats,
            selectedDate: selectedDate,
            today: today,
          ),
        ],
      ],
    );
  }
}

// ── Top Day Card + 7-Day Interactive Strip ───────────────────────────────────

class _DayHeaderCard extends ConsumerWidget {
  const _DayHeaderCard({
    required this.state,
    required this.habitStats,
    required this.selectedDate,
    required this.today,
  });

  final SupplementDayState state;
  final SupplementHabitStats habitStats;
  final DateTime selectedDate;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final done = state.totalCount > 0 && state.progress >= 1.0;
    final isToday = _isSameDay(selectedDate, today);

    // Last 7 days ending today for the quick strip.
    final stripPoints = habitStats.heatmapPoints.length >= 7
        ? habitStats.heatmapPoints.sublist(habitStats.heatmapPoints.length - 7)
        : habitStats.dailyPoints;

    return HxCard(
      accent: _accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isToday
                              ? 'TODAY'
                              : DateFormat(
                                  'EEE, d MMM',
                                ).format(selectedDate).toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _accent,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        if (!isToday) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              Haptics.selection();
                              ref
                                      .read(
                                        supplementSelectedDateProvider.notifier,
                                      )
                                      .state =
                                  today;
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Back to today',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _accent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: HxSpace.x1),
                    Text(
                      state.totalCount == 0
                          ? 'Nothing to track yet'
                          : done
                          ? 'All taken ✓'
                          : '${state.takenCount} of ${state.totalCount} taken',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: habitStats.currentStreak > 0
                        ? Colors.orange.withValues(alpha: 0.14)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: habitStats.currentStreak > 0
                          ? Colors.orange.withValues(alpha: 0.4)
                          : AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                        color: habitStats.currentStreak > 0
                            ? Colors.orange
                            : AppColors.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${habitStats.currentStreak}d streak',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: habitStats.currentStreak > 0
                              ? Colors.orange
                              : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (state.totalCount > 0) ...[
            const SizedBox(height: HxSpace.x3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: state.progress),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    done ? _perfectGreen : _accent,
                  ),
                ),
              ),
            ),
            if (stripPoints.isNotEmpty) ...[
              const SizedBox(height: HxSpace.x4),
              Row(
                children: [
                  for (final p in stripPoints)
                    Expanded(
                      child: _WeekStripCell(
                        point: p,
                        isSelected: _isSameDay(p.date, selectedDate),
                        isToday: _isSameDay(p.date, today),
                        onTap: () {
                          Haptics.selection();
                          ref
                                  .read(supplementSelectedDateProvider.notifier)
                                  .state =
                              p.date;
                        },
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WeekStripCell extends StatelessWidget {
  const _WeekStripCell({
    required this.point,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final SupplementDayPoint point;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = point.completionRatio;
    final isPerfect = point.isPerfect;
    final dayLabel = DateFormat('E').format(point.date).substring(0, 2);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _accent
                : isToday
                ? _accent.withValues(alpha: 0.35)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dayLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: isSelected ? _accent : AppColors.secondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: ratio > 0 ? ratio : 0,
                    strokeWidth: 2.5,
                    backgroundColor: AppColors.outlineVariant.withValues(
                      alpha: 0.25,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPerfect ? _perfectGreen : _accent,
                    ),
                  ),
                  if (isPerfect)
                    const Icon(Icons.check, size: 13, color: _perfectGreen)
                  else
                    Text(
                      '${point.date.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supplement Checklist Row with Mini 7-Day Habit Chain ─────────────────────

class _Row extends ConsumerWidget {
  const _Row({
    required this.supplement,
    required this.isTaken,
    required this.selectedDate,
    required this.isToday,
    this.itemStat,
  });

  final Supplement supplement;
  final bool isTaken;
  final DateTime selectedDate;
  final bool isToday;
  final SupplementItemHabitStat? itemStat;

  String? get _subtitle {
    final parts = <String?>[
      supplement.brand,
      supplement.doseLabel,
      switch (supplement.schedule) {
        SupplementSchedule.time => supplement.timeHHMM,
        SupplementSchedule.postWorkout => 'Post-workout',
        SupplementSchedule.none => null,
      },
    ].whereType<String>().where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = _subtitle;
    final streak = itemStat?.currentStreak ?? 0;
    final last7 = itemStat?.last7Days ?? const <bool>[];

    return GestureDetector(
      onLongPress: () =>
          SupplementEditSheet.show(context, existing: supplement),
      child: HxCard(
        onTap: () {
          Haptics.selection();
          final repo = ref.read(supplementRepositoryProvider);
          if (isToday) {
            repo.markTaken(supplement.id, !isTaken);
          } else {
            repo.markTakenForDate(supplement.id, !isTaken, selectedDate);
          }
        },
        padding: const EdgeInsets.symmetric(
          horizontal: HxSpace.x4,
          vertical: HxSpace.x3,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTaken ? _accent : Colors.transparent,
                border: Border.all(
                  color: isTaken ? _accent : theme.colorScheme.outlineVariant,
                  width: 1.8,
                ),
              ),
              child: isTaken
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          supplement.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: isTaken
                                ? TextDecoration.lineThrough
                                : null,
                            color: isTaken ? muted : null,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (streak > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🔥 ${streak}d',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (last7.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '7d: ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            color: muted,
                          ),
                        ),
                        for (final taken in last7)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: taken
                                  ? _accent
                                  : theme.colorScheme.outlineVariant.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: muted,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  SupplementEditSheet.show(context, existing: supplement),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Habit Tracking & Consistency Analytics Section ───────────────────────────

class _HabitAnalyticsSection extends ConsumerWidget {
  const _HabitAnalyticsSection({
    required this.stats,
    required this.selectedDate,
    required this.today,
  });

  final SupplementHabitStats stats;
  final DateTime selectedDate;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rangeDays = ref.watch(supplementHabitRangeDaysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header + Range Selector (7D / 30D / 90D)
        Row(
          children: [
            const Icon(Icons.insights_rounded, size: 18, color: _accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'HABIT TRACKING & CONSISTENCY',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            for (final days in const [7, 30, 90]) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  label: Text('${days}D'),
                  selected: rangeDays == days,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    Haptics.selection();
                    ref.read(supplementHabitRangeDaysProvider.notifier).state =
                        days;
                  },
                  selectedColor: _accent.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: rangeDays == days
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: rangeDays == days ? _accent : AppColors.secondary,
                  ),
                  side: BorderSide(
                    color: rangeDays == days
                        ? _accent
                        : AppColors.outlineVariant.withValues(alpha: 0.35),
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: HxSpace.x3),

        // 4 Habit KPI Summary Cards (2x2 Grid)
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                icon: Icons.verified_outlined,
                iconColor: _accent,
                label: 'Consistency (${rangeDays}D)',
                value: '${(stats.consistencyRate * 100).round()}%',
                subtitle: stats.effectiveWindowDays > 0
                    ? 'Over ${stats.effectiveWindowDays} active days'
                    : 'No entries yet',
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Expanded(
              child: _KpiTile(
                icon: Icons.local_fire_department_rounded,
                iconColor: Colors.orange,
                label: 'Current Streak',
                value: '${stats.currentStreak} days',
                subtitle: 'Best: ${stats.bestStreak} days',
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x2),
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                icon: Icons.check_circle_outline_rounded,
                iconColor: _perfectGreen,
                label: 'Perfect Days',
                value: '${stats.perfectDays} / ${stats.rangeDays}',
                subtitle: '100% of all supplements',
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Expanded(
              child: _KpiTile(
                icon: Icons.medication_liquid_rounded,
                iconColor: Colors.cyanAccent,
                label: 'Doses Taken',
                value: '${stats.totalDosesTaken}',
                subtitle: 'Active days: ${stats.activeDays}d',
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x4),

        // Adherence Trend Chart (BarChart for 7D, LineChart for 30D/90D)
        _AdherenceTrendChartCard(stats: stats),
        const SizedBox(height: HxSpace.x4),

        // 28-Day Habit Heatmap Matrix
        _HabitHeatmapCard(
          points: stats.heatmapPoints,
          selectedDate: selectedDate,
          today: today,
          onSelectDate: (date) {
            Haptics.selection();
            ref.read(supplementSelectedDateProvider.notifier).state = date;
          },
        ),
        const SizedBox(height: HxSpace.x4),

        // Per-Supplement Consistency Breakdown
        _PerSupplementConsistencyCard(stats: stats),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HxCard(
      padding: const EdgeInsets.all(HxSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 10.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Adherence Trend Chart Card (`fl_chart`) ──────────────────────────────────

class _AdherenceTrendChartCard extends StatelessWidget {
  const _AdherenceTrendChartCard({required this.stats});

  final SupplementHabitStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = stats.dailyPoints;

    return HxCard(
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
                      'Consistency Chart (${stats.rangeDays} days)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Daily supplement adherence rate (%)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Avg. ${(stats.consistencyRate * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: points.isEmpty
                ? const Center(child: Text('No data'))
                : stats.rangeDays <= 7
                ? _build7DayBarChart(theme, points)
                : _buildMultiDayLineChart(theme, points),
          ),
        ],
      ),
    );
  }

  Widget _build7DayBarChart(ThemeData theme, List<SupplementDayPoint> points) {
    return BarChart(
      BarChartData(
        maxY: 100,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.outlineVariant.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 50,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) {
                  return const SizedBox.shrink();
                }
                final label = DateFormat('E').format(points[idx].date);
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: AppColors.secondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainer,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= points.length) return null;
              final p = points[groupIndex];
              final dStr = DateFormat('MMM d').format(p.date);
              return BarTooltipItem(
                '$dStr\n${p.takenCount}/${p.totalCount} (${(p.completionRatio * 100).round()}%)',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (int i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (points[i].completionRatio * 100).clamp(0, 100),
                  width: 18,
                  borderRadius: BorderRadius.circular(6),
                  color: points[i].isPerfect ? _perfectGreen : _accent,
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 100,
                    color: AppColors.surfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMultiDayLineChart(
    ThemeData theme,
    List<SupplementDayPoint> points,
  ) {
    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), (points[i].completionRatio * 100).clamp(0, 100)),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 0,
        maxY: 105,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (val) => FlLine(
            color: AppColors.outlineVariant.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 100,
              color: _perfectGreen.withValues(alpha: 0.45),
              strokeWidth: 1.2,
              dashArray: [4, 4],
            ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 50,
              getTitlesWidget: (value, meta) {
                if (value > 100) return const SizedBox.shrink();
                return Text(
                  '${value.toInt()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: AppColors.secondary,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (points.length / 4).clamp(1.0, 30.0),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) {
                  return const SizedBox.shrink();
                }
                final label = DateFormat('d.M.').format(points[idx].date);
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: AppColors.secondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainer,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                if (idx < 0 || idx >= points.length) return null;
                final p = points[idx];
                final dStr = DateFormat('MMM d').format(p.date);
                return LineTooltipItem(
                  '$dStr\n${p.takenCount}/${p.totalCount} (${spot.y.round()}%)',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: _accent,
            barWidth: 2.8,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 30,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 2.5,
                    color: spot.y >= 100 ? _perfectGreen : _accent,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: _accent.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 28-Day Habit Heatmap Grid ────────────────────────────────────────────────

class _HabitHeatmapCard extends StatelessWidget {
  const _HabitHeatmapCard({
    required this.points,
    required this.selectedDate,
    required this.today,
    required this.onSelectDate,
  });

  final List<SupplementDayPoint> points;
  final DateTime selectedDate;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDate;

  Color _cellColor(SupplementDayPoint p) {
    if (p.isPerfect) return _perfectGreen;
    final r = p.completionRatio;
    if (r >= 0.5) return _accent.withValues(alpha: 0.75);
    if (r > 0) return _accent.withValues(alpha: 0.38);
    return AppColors.surfaceVariant.withValues(alpha: 0.65);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return HxCard(
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
                      'Habit Calendar (Last 28 Days)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tap any day to review or log past supplement doses',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: points.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final p = points[index];
              final isSelected = _isSameDay(p.date, selectedDate);
              final isToday = _isSameDay(p.date, today);
              return GestureDetector(
                onTap: () => onSelectDate(p.date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _cellColor(p),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : isToday
                          ? _accent
                          : Colors.transparent,
                      width: isSelected ? 2 : 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${p.date.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: p.hasAnyTaken
                              ? Colors.white
                              : AppColors.secondary,
                        ),
                      ),
                      if (p.totalCount > 0 && p.hasAnyTaken)
                        Text(
                          '${p.takenCount}/${p.totalCount}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _LegendDot(
                color: AppColors.surfaceVariant.withValues(alpha: 0.65),
                label: '0%',
              ),
              const SizedBox(width: 10),
              _LegendDot(
                color: _accent.withValues(alpha: 0.4),
                label: 'Partial',
              ),
              const SizedBox(width: 10),
              _LegendDot(color: _accent.withValues(alpha: 0.78), label: '50%+'),
              const SizedBox(width: 10),
              const _LegendDot(color: _perfectGreen, label: '100%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }
}

// ── Per-Supplement Consistency Breakdown Card ────────────────────────────────

class _PerSupplementConsistencyCard extends StatelessWidget {
  const _PerSupplementConsistencyCard({required this.stats});

  final SupplementHabitStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stats.itemStats.isEmpty) return const SizedBox.shrink();

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Per-Supplement Consistency (${stats.rangeDays}D)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Adherence rate per supplement & last 14 days',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < stats.itemStats.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _PerSupplementItemRow(item: stats.itemStats[i]),
          ],
        ],
      ),
    );
  }
}

class _PerSupplementItemRow extends StatelessWidget {
  const _PerSupplementItemRow({required this.item});

  final SupplementItemHabitStat item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (item.adherenceRate * 100).round();
    final barColor = pct >= 85
        ? _perfectGreen
        : pct >= 50
        ? _accent
        : Colors.amber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.supplement.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.currentStreak > 0) ...[
              Text(
                '🔥 ${item.currentStreak}d',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '$pct% (${item.takenDays}/${item.activeWindowDays}d)',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: item.adherenceRate,
            minHeight: 5,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        if (item.last14Days.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '14d:',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    for (final taken in item.last14Days)
                      Expanded(
                        child: Container(
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: taken
                                ? barColor
                                : AppColors.outlineVariant.withValues(
                                    alpha: 0.25,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
