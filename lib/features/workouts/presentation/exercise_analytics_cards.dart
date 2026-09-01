import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/presentation/analytics_providers.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/tokens/tokens.dart';
import 'package:herculex/ui/hx_card.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class SessionVariantStats {
  final DateTime date;
  final String variant;
  final double e1rm;
  final double volumeKg;

  SessionVariantStats({
    required this.date,
    required this.variant,
    required this.e1rm,
    required this.volumeKg,
  });
}

List<SessionVariantStats> _extractTrendData(
  TrainingSnapshot snapshot,
  int exerciseId,
  LoggingMetric metric,
) {
  final map = <String, Map<DateTime, SessionVariantStats>>{};

  for (final resolved in snapshot.sets) {
    if (resolved.exercise.id != exerciseId) continue;

    final date = resolved.session.endedAt ?? resolved.session.startedAt;
    final day = DateTime(date.year, date.month, date.day);

    var variant = resolved.accessoryCombo;
    if (variant == 'Raw' &&
        resolved.equipmentVariant != resolved.exercise.modality) {
      variant = resolved.equipmentVariant;
    }

    final e1rm =
        OneRepMax.estimate(
          weightKg: resolved.effectiveKg,
          reps: resolved.set.reps,
        ) ??
        resolved.effectiveKg;

    final volume = resolved.tonnageKg;

    map.putIfAbsent(variant, () => {});
    final current = map[variant]![day];

    if (current == null) {
      map[variant]![day] = SessionVariantStats(
        date: day,
        variant: variant,
        e1rm: e1rm,
        volumeKg: volume,
      );
    } else {
      map[variant]![day] = SessionVariantStats(
        date: day,
        variant: variant,
        e1rm: e1rm > current.e1rm ? e1rm : current.e1rm,
        volumeKg: current.volumeKg + volume,
      );
    }
  }

  final allStats = <SessionVariantStats>[];
  for (final variantMap in map.values) {
    allStats.addAll(variantMap.values);
  }
  allStats.sort((a, b) => a.date.compareTo(b.date));
  return allStats;
}

class AdvancedTrendCard extends ConsumerStatefulWidget {
  final int exerciseId;
  final LoggingMetric metric;

  const AdvancedTrendCard({
    super.key,
    required this.exerciseId,
    required this.metric,
  });

  @override
  ConsumerState<AdvancedTrendCard> createState() => _AdvancedTrendCardState();
}

class _AdvancedTrendCardState extends ConsumerState<AdvancedTrendCard> {
  int _selectedMode = 0; // 0 = 1RM, 1 = Volume

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(trainingSnapshotProvider);
    return HxCard(
      child: snapshotAsync.when(
        loading: () => const SizedBox(
          height: 44,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (error, _) => Text('Could not load trend: $error'),
        data: (snapshot) {
          final stats = _extractTrendData(
            snapshot,
            widget.exerciseId,
            widget.metric,
          );
          if (stats.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Advanced Trends',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Complete a working set to start this trend.',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ],
            );
          }
          return _buildContent(context, stats);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<SessionVariantStats> stats) {
    final hx = context.hx;

    // Extract unique variants and dates
    final variants = stats.map((s) => s.variant).toSet().toList();
    final dates = stats.map((s) => s.date).toSet().toList()..sort();

    // Map dates to X axis values (0, 1, 2...)
    final dateToX = {
      for (var i = 0; i < dates.length; i++) dates[i]: i.toDouble(),
    };

    // Colors for variants
    final colors = [
      hx.primary,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.red,
    ];

    final lineBarsData = <LineChartBarData>[];

    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (var i = 0; i < variants.length; i++) {
      final variant = variants[i];
      final variantStats = stats.where((s) => s.variant == variant).toList();

      final spots = variantStats.map((s) {
        final y = _selectedMode == 0 ? s.e1rm : s.volumeKg;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        return FlSpot(dateToX[s.date]!, y);
      }).toList();

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[i % colors.length],
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    if (minY == double.infinity) minY = 0;
    if (maxY == double.negativeInfinity) maxY = 10;

    final spread = (maxY - minY).abs();
    final padding = spread < 1 ? 8.0 : spread * 0.18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Performance Trends',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 0, label: Text('1RM')),
                ButtonSegment<int>(value: 1, label: Text('Vol')),
              ],
              selected: {_selectedMode},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _selectedMode = newSelection.first;
                });
              },
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (dates.length > 1 ? dates.length - 1 : 1).toDouble(),
              minY: math.max(0, minY - padding),
              maxY: maxY + padding,
              lineBarsData: lineBarsData,
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          value.toStringAsFixed(0),
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (variants.length > 1) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(variants.length, (i) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(variants[i], style: const TextStyle(fontSize: 12)),
                ],
              );
            }),
          ),
        ],
      ],
    );
  }
}

class ResistanceProfileCard extends ConsumerWidget {
  final int exerciseId;
  final LoggingMetric metric;

  const ResistanceProfileCard({
    super.key,
    required this.exerciseId,
    required this.metric,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!metric.isRepBased) return const SizedBox.shrink();

    final snapshotAsync = ref.watch(trainingSnapshotProvider);
    return snapshotAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (snapshot) {
        double maxRaw = 0;
        double maxAccommodating = 0;
        bool hasAccommodating = false;

        for (final resolved in snapshot.sets) {
          if (resolved.exercise.id != exerciseId) continue;

          final e1rm =
              OneRepMax.estimate(
                weightKg: resolved.effectiveKg,
                reps: resolved.set.reps,
              ) ??
              resolved.effectiveKg;

          final hasBandsOrChains =
              resolved.bands.isNotEmpty || (resolved.set.chainsKg ?? 0) > 0;
          if (hasBandsOrChains) {
            hasAccommodating = true;
            if (e1rm > maxAccommodating) maxAccommodating = e1rm;
          } else {
            if (e1rm > maxRaw) maxRaw = e1rm;
          }
        }

        if (!hasAccommodating || maxRaw == 0 || maxAccommodating == 0)
          return const SizedBox.shrink();

        final diff = maxAccommodating - maxRaw;
        final dartDiffStr = diff > 0
            ? "+${diff.toStringAsFixed(1)}kg"
            : "${diff.toStringAsFixed(1)}kg";
        final pctStr = ((diff / maxRaw) * 100).toStringAsFixed(0);

        final isStrongerWithResistance = diff > 0;

        return HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resistance Profile',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatBox(
                    label: 'Raw 1RM',
                    value: '${maxRaw.toStringAsFixed(1)}kg',
                  ),
                  StatBox(
                    label: 'With Bands/Chains',
                    value: '${maxAccommodating.toStringAsFixed(1)}kg',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isStrongerWithResistance
                    ? 'You are stronger with accommodating resistance ($dartDiffStr / $pctStr%). This suggests your lockout is strong, but you might be weaker at the bottom of the movement.'
                    : 'You are weaker with accommodating resistance ($dartDiffStr / $pctStr%). This suggests your lockout might need work or the resistance curve is challenging.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.secondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StatBox extends StatelessWidget {
  final String label;
  final String value;

  const StatBox({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.hx.outlineVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.secondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class CalisthenicsStatsCard extends ConsumerWidget {
  final ExerciseCatalogData exercise;
  final LoggingMetric metric;

  const CalisthenicsStatsCard({
    super.key,
    required this.exercise,
    required this.metric,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!metric.isRepBased) return const SizedBox.shrink();
    if (!exercise.supportsWeightedBodyweight &&
        exercise.modality != 'bodyweight' &&
        exercise.modality != 'weighted') {
      return const SizedBox.shrink();
    }

    final snapshotAsync = ref.watch(trainingSnapshotProvider);
    return snapshotAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (snapshot) {
        int maxRepsSet = 0;
        int maxRepsSession = 0;
        double maxFreeweight1rm = 0;
        double maxWeighted1rm = 0;

        final sessionReps = <DateTime, int>{};

        for (final resolved in snapshot.sets) {
          if (resolved.exercise.id != exercise.id) continue;

          final reps = resolved.set.reps;
          if (reps > maxRepsSet) maxRepsSet = reps;

          final date = resolved.session.endedAt ?? resolved.session.startedAt;
          final day = DateTime(date.year, date.month, date.day);

          final existingReps = sessionReps[day];
          sessionReps[day] = (existingReps == null ? 0 : existingReps) + reps;

          final e1rm =
              OneRepMax.estimate(
                weightKg: resolved.effectiveKg,
                reps: resolved.set.reps,
              ) ??
              resolved.effectiveKg;

          final isWeighted =
              (resolved.equipmentVariant ?? exercise.modality) == 'weighted' ||
              (resolved.set.weightKg > 0);
          if (isWeighted) {
            if (e1rm > maxWeighted1rm) maxWeighted1rm = e1rm;
          } else {
            if (e1rm > maxFreeweight1rm) maxFreeweight1rm = e1rm;
          }
        }

        for (final reps in sessionReps.values) {
          if (reps > maxRepsSession) maxRepsSession = reps;
        }

        if (maxRepsSet == 0) return const SizedBox.shrink();

        return HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calisthenics Stats',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatBox(label: 'Max Reps / Set', value: '${maxRepsSet}x'),
                  StatBox(
                    label: 'Max Reps / Session',
                    value: '${maxRepsSession}x',
                  ),
                ],
              ),
              if (maxFreeweight1rm > 0 && maxWeighted1rm > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Freeweight 1RM: ${maxFreeweight1rm.toStringAsFixed(1)}kg\nWeighted 1RM: ${maxWeighted1rm.toStringAsFixed(1)}kg',
                  style: TextStyle(color: AppColors.secondary, fontSize: 13),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ExerciseTimelineCard extends ConsumerWidget {
  final int exerciseId;

  const ExerciseTimelineCard({super.key, required this.exerciseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(trainingSnapshotProvider);
    return snapshotAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (snapshot) {
        final sessions = <DateTime, List<ResolvedSet>>{};
        for (final resolved in snapshot.sets) {
          if (resolved.exercise.id != exerciseId) continue;
          final date = resolved.session.endedAt ?? resolved.session.startedAt;
          final day = DateTime(date.year, date.month, date.day);
          sessions.putIfAbsent(day, () => []).add(resolved);
        }

        if (sessions.isEmpty) return const SizedBox.shrink();

        final sortedDays = sessions.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        final recentDays = sortedDays.take(5).toList();
        final format = DateFormat('MMM d, yyyy');

        return HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Sessions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...recentDays.map((day) {
                final daySets = sessions[day]!;
                final totalVolume = daySets.fold<double>(
                  0.0,
                  (sum, s) => sum + s.tonnageKg,
                );
                final topSet = daySets.reduce(
                  (a, b) => a.effectiveKg > b.effectiveKg ? a : b,
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          format.format(day),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${daySets.length} sets • Vol: ${totalVolume.toStringAsFixed(0)}kg',
                            ),
                            Text(
                              'Top: ${topSet.set.reps}x${topSet.set.weightKg}kg',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
