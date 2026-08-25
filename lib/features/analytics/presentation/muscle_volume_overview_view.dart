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
    final selectedRegion = ref.watch(volumeRegionFilterProvider);
    final selectedSort = ref.watch(volumeSortByProvider);

    return HxScreenShell(
      title: 'Volume Breakdown',
      children: [
        overviewAsync.when(
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderSummaryCard(data: data),
              const SizedBox(height: HxSpace.x4),
              _TimeframeSelector(currentTimeframe: selectedTimeframe),
              const SizedBox(height: HxSpace.x4),
              _FilterAndSortBar(
                currentRegion: selectedRegion,
                currentSort: selectedSort,
              ),
              const SizedBox(height: HxSpace.x4),
              _MuscleGroupList(
                data: data,
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
  const _HeaderSummaryCard({required this.data});

  final MuscleVolumeOverviewData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);

    return HxCard(
      accent: hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL VOLUME',
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
            weight.formatTonnage(data.totalTonnageKg),
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
                  label: 'Working Sets',
                  value: '${data.totalSets}',
                  icon: Icons.fitness_center,
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: _MetricTile(
                  label: 'Workouts',
                  value: '${data.totalWorkouts}',
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

// ── 2. Timeframe Selector ────────────────────────────────────────────────────

class _TimeframeSelector extends ConsumerWidget {
  const _TimeframeSelector({required this.currentTimeframe});

  final VolumeTimeframe currentTimeframe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tf in VolumeTimeframe.values) ...[
            GestureDetector(
              onTap: () {
                Haptics.selection();
                ref.read(selectedVolumeTimeframeProvider.notifier).state = tf;
              },
              child: AnimatedContainer(
                duration: HxMotion.base,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tf == currentTimeframe
                      ? hx.primary
                      : hx.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(HxRadius.pill),
                  border: Border.all(
                    color: tf == currentTimeframe
                        ? hx.primary
                        : hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  tf.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: tf == currentTimeframe
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: tf == currentTimeframe
                        ? Colors.white
                        : hx.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: HxSpace.x2),
          ],
        ],
      ),
    );
  }
}

// ── 3. Filter & Sort Bar ─────────────────────────────────────────────────────

class _FilterAndSortBar extends ConsumerWidget {
  const _FilterAndSortBar({
    required this.currentRegion,
    required this.currentSort,
  });

  final MuscleRegionFilter currentRegion;
  final MuscleVolumeSort currentSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in MuscleRegionFilter.values) ...[
                  InkWell(
                    onTap: () {
                      Haptics.selection();
                      ref.read(volumeRegionFilterProvider.notifier).state = r;
                    },
                    borderRadius: BorderRadius.circular(HxRadius.pill),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: r == currentRegion
                            ? hx.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(HxRadius.pill),
                        border: Border.all(
                          color: r == currentRegion
                              ? hx.primary
                              : hx.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        r.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: r == currentRegion
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: r == currentRegion
                              ? hx.primary
                              : hx.secondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HxSpace.x2),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: HxSpace.x2),
        PopupMenuButton<MuscleVolumeSort>(
          initialValue: currentSort,
          onSelected: (sort) {
            Haptics.selection();
            ref.read(volumeSortByProvider.notifier).state = sort;
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HxRadius.lg),
          ),
          color: hx.surfaceContainerLowest,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(HxRadius.pill),
              border: Border.all(
                color: hx.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort, size: 14, color: hx.secondary),
                const SizedBox(width: 4),
                Text(
                  currentSort.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            for (final s in MuscleVolumeSort.values)
              PopupMenuItem(
                value: s,
                child: Text(
                  s.label,
                  style: TextStyle(
                    color: s == currentSort ? hx.primary : hx.onSurface,
                    fontWeight: s == currentSort
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── 4. Muscle Group List ─────────────────────────────────────────────────────

class _MuscleGroupList extends ConsumerWidget {
  const _MuscleGroupList({
    required this.data,
    required this.regionFilter,
    required this.sort,
  });

  final MuscleVolumeOverviewData data;
  final MuscleRegionFilter regionFilter;
  final MuscleVolumeSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);

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
                          weight.formatTonnage(item.tonnageKg),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: item.tonnageKg > 0 ? hx.primary : hx.secondary,
                          ),
                        ),
                        Text(
                          '${item.sets.toStringAsFixed(item.sets < 10 && item.sets > 0 ? 1 : 0)} sets',
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
