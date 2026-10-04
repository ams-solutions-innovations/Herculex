import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/units.dart';
import '../../../theme/haptics.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../domain/muscle_volume_details.dart';
import 'muscle_volume_providers.dart';

/// Muscle Volume Overview page listing all 19 muscle groups, their tonnage,
/// sets, and historical distribution over a selectable timeframe.
class MuscleVolumeOverviewView extends ConsumerWidget {
  const MuscleVolumeOverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(muscleVolumeOverviewProvider);
    final selectedTimeframe = ref.watch(selectedVolumeTimeframeProvider);
    final displayMode = ref.watch(volumeMetricDisplayModeProvider);
    final selectedRegion = ref.watch(volumeRegionFilterProvider);
    final selectedSort = ref.watch(volumeSortByProvider);

    return HxScreenShell(
      title: 'Volume Breakdown',
      children: [
        overviewAsync.when(
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderSummaryCard(
                data: data,
                displayMode: displayMode,
              ),
              const SizedBox(height: HxSpace.x4),
              _TimeframeAndModeSelector(
                currentTimeframe: selectedTimeframe,
                currentMode: displayMode,
              ),
              const SizedBox(height: HxSpace.x2),
              _FilterAndSortBar(
                currentRegion: selectedRegion,
                currentSort: selectedSort,
              ),
              const SizedBox(height: HxSpace.x4),
              _MuscleGroupList(
                data: data,
                displayMode: displayMode,
                regionFilter: selectedRegion,
                sort: selectedSort,
              ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(HxSpace.x6),
              child: Text(
                'Failed to load muscle volume: $e',
                style: TextStyle(color: context.hx.danger),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 1. Top Summary Card ──────────────────────────────────────────────────────

class _HeaderSummaryCard extends ConsumerWidget {
  const _HeaderSummaryCard({
    required this.data,
    required this.displayMode,
  });

  final MuscleVolumeOverviewData data;
  final VolumeMetricDisplayMode displayMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);
    final isWeekly = displayMode == VolumeMetricDisplayMode.weeklyAvg;

    final tonnageStr = isWeekly
        ? '${weight.formatTonnage(data.weeklyAverageTonnageKg)} / wk'
        : weight.formatTonnage(data.totalTonnageKg);

    final setsStr = isWeekly
        ? data.weeklyAverageSets.toStringAsFixed(1)
        : '${data.totalSets}';

    final workoutsStr = isWeekly
        ? data.weeklyAverageWorkouts.toStringAsFixed(1)
        : '${data.totalWorkouts}';

    return HxCard(
      accent: hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isWeekly ? 'AVG. WEEKLY VOLUME' : 'TOTAL VOLUME',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  data.timeframe.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Text(
            tonnageStr,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: hx.primary,
            ),
          ),
          const SizedBox(height: HxSpace.x4),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: isWeekly ? 'Sets / Wk' : 'Working Sets',
                  value: setsStr,
                  icon: Icons.fitness_center,
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: _MetricTile(
                  label: isWeekly ? 'Workouts / Wk' : 'Workouts',
                  value: workoutsStr,
                  icon: Icons.event_available,
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: _MetricTile(
                  label: 'Exercises',
                  value: '${data.totalExercises}',
                  icon: Icons.format_list_bulleted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      padding: const EdgeInsets.all(HxSpace.x3),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(HxRadius.lg),
        border: Border.all(
          color: hx.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: hx.secondary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── 2 & 3. Filter menus ──────────────────────────────────────────────────────
//
// Every filter is a pop-up menu rather than a horizontally scrolling chip row,
// so all options are visible at once and nothing is clipped off-screen.

class _TimeframeAndModeSelector extends ConsumerWidget {
  const _TimeframeAndModeSelector({
    required this.currentTimeframe,
    required this.currentMode,
  });

  final VolumeTimeframe currentTimeframe;
  final VolumeMetricDisplayMode currentMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _FilterMenu<VolumeTimeframe>(
            icon: Icons.calendar_today_rounded,
            value: currentTimeframe,
            values: VolumeTimeframe.values,
            labelOf: (tf) => tf.label,
            onSelected: (tf) =>
                ref.read(selectedVolumeTimeframeProvider.notifier).state = tf,
          ),
        ),
        const SizedBox(width: HxSpace.x2),
        Expanded(
          child: _FilterMenu<VolumeMetricDisplayMode>(
            icon: Icons.bar_chart_rounded,
            value: currentMode,
            values: VolumeMetricDisplayMode.values,
            labelOf: (m) => m.label,
            onSelected: (m) =>
                ref.read(volumeMetricDisplayModeProvider.notifier).state = m,
          ),
        ),
      ],
    );
  }
}

class _FilterAndSortBar extends ConsumerWidget {
  const _FilterAndSortBar({
    required this.currentRegion,
    required this.currentSort,
  });

  final MuscleRegionFilter currentRegion;
  final MuscleVolumeSort currentSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _FilterMenu<MuscleRegionFilter>(
            icon: Icons.accessibility_new_rounded,
            value: currentRegion,
            values: MuscleRegionFilter.values,
            labelOf: (r) => r.label,
            onSelected: (r) =>
                ref.read(volumeRegionFilterProvider.notifier).state = r,
          ),
        ),
        const SizedBox(width: HxSpace.x2),
        Expanded(
          child: _FilterMenu<MuscleVolumeSort>(
            icon: Icons.sort,
            value: currentSort,
            values: MuscleVolumeSort.values,
            labelOf: (s) => s.label,
            onSelected: (s) =>
                ref.read(volumeSortByProvider.notifier).state = s,
          ),
        ),
      ],
    );
  }
}

/// A pill showing the current choice that opens a pop-up menu of all options.
class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.icon,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onSelected,
  });

  final IconData icon;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: (v) {
        Haptics.selection();
        onSelected(v);
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HxRadius.lg),
      ),
      color: hx.surfaceContainerLowest,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final v in values)
          PopupMenuItem<T>(
            value: v,
            child: Text(
              labelOf(v),
              style: TextStyle(
                color: v == value ? hx.primary : hx.onSurface,
                fontWeight: v == value ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(HxRadius.pill),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: hx.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labelOf(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hx.onSurface,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: hx.secondary),
          ],
        ),
      ),
    );
  }
}

// ── 4. Muscle Group List ─────────────────────────────────────────────────────

class _MuscleGroupList extends ConsumerWidget {
  const _MuscleGroupList({
    required this.data,
    required this.displayMode,
    required this.regionFilter,
    required this.sort,
  });

  final MuscleVolumeOverviewData data;
  final VolumeMetricDisplayMode displayMode;
  final MuscleRegionFilter regionFilter;
  final MuscleVolumeSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);
    final isWeekly = displayMode == VolumeMetricDisplayMode.weeklyAvg;
    final weeks = data.weeksCount;

    // 1. Filter by region
    var list = data.groups.where((g) {
      switch (regionFilter) {
        case MuscleRegionFilter.upper:
          return g.region == MuscleRegion.upper;
        case MuscleRegionFilter.lower:
          return g.region == MuscleRegion.lower;
        case MuscleRegionFilter.core:
          return g.region == MuscleRegion.core;
        case MuscleRegionFilter.all:
          return true;
      }
    }).toList();

    // 2. Sort
    switch (sort) {
      case MuscleVolumeSort.volumeDesc:
        list.sort((a, b) {
          final cmp = b.tonnageKg.compareTo(a.tonnageKg);
          if (cmp != 0) return cmp;
          return b.sets.compareTo(a.sets);
        });
      case MuscleVolumeSort.setsDesc:
        list.sort((a, b) {
          final cmp = b.sets.compareTo(a.sets);
          if (cmp != 0) return cmp;
          return b.tonnageKg.compareTo(a.tonnageKg);
        });
      case MuscleVolumeSort.nameAsc:
        list.sort((a, b) => a.muscle.compareTo(b.muscle));
    }

    return Column(
      children: [
        for (final item in list) ...[
          HxCard(
            onTap: () => context.push(
              '/muscle-volume/${Uri.encodeComponent(item.muscle)}',
            ),
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
                                item.muscle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: hx.outlineVariant.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.region.label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: hx.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.workoutCount == 0
                                ? 'No workouts logged in this period'
                                : isWeekly
                                    ? '${item.workoutCount} workouts (${item.weeklyWorkouts(weeks).toStringAsFixed(1)}/wk) • Last: ${_formatLastTrained(item.lastTrained)}'
                                    : '${item.workoutCount} workouts • ${item.exerciseCount} exercises • Last: ${_formatLastTrained(item.lastTrained)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hx.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isWeekly
                              ? '${weight.formatTonnage(item.weeklyTonnageKg(weeks))} / wk'
                              : weight.formatTonnage(item.tonnageKg),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: item.tonnageKg > 0 ? hx.primary : hx.secondary,
                          ),
                        ),
                        Text(
                          isWeekly
                              ? '${item.weeklySets(weeks).toStringAsFixed(1)} sets / wk'
                              : '${item.sets.toStringAsFixed(item.sets < 10 && item.sets > 0 ? 1 : 0)} sets',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hx.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: hx.secondary.withValues(alpha: 0.6),
                    ),
                  ],
                ),
                if (item.percentageOfMax > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.percentageOfMax,
                      minHeight: 4,
                      backgroundColor: hx.surfaceVariant.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(hx.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: HxSpace.x3),
        ],
      ],
    );
  }

  String _formatLastTrained(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final trainedDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(trainedDay).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) return '${diffDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}
