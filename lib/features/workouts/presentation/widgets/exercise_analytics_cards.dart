import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';
import 'package:intl/intl.dart';

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
    if (resolved.exercise.id != exerciseId ||
        isMachineAssistedPullup(resolved.exercise.slug)) {
      continue;
    }

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
    final peakValue = stats
        .map((s) => _selectedMode == 0 ? s.e1rm : s.volumeKg)
        .fold<double>(0, (current, value) => value > current ? value : current);

    // Map dates to X axis values (0, 1, 2...)
    final dateToX = {
      for (var i = 0; i < dates.length; i++) dates[i]: i.toDouble(),
    };

    // Colors for variants
    final colors = [
      hx.primary,
      hx.domainRecovery,
      hx.domainNutrition,
      hx.quickAdd,
      hx.domainFasting,
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
          preventCurveOverShooting: true,
          gradient: LinearGradient(
            colors: [
              colors[i % colors.length],
              Color.lerp(colors[i % colors.length], hx.tertiary, 0.28)!,
            ],
          ),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: spots.length < 18,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3,
              color: colors[i % colors.length],
              strokeWidth: 2,
              strokeColor: hx.surfaceContainerLowest,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors[i % colors.length].withValues(alpha: 0.2),
                colors[i % colors.length].withValues(alpha: 0.01),
              ],
            ),
          ),
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
        const SizedBox(height: 14),
        Row(
          children: [
            StatBox(label: 'Training days', value: '${dates.length}'),
            const SizedBox(width: 10),
            StatBox(
              label: _selectedMode == 0 ? 'Peak estimate' : 'Peak volume',
              value: '${peakValue.toStringAsFixed(1)} kg',
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (dates.length > 1 ? dates.length - 1 : 1).toDouble(),
              minY: math.max(0, minY - padding),
              maxY: maxY + padding,
              lineBarsData: lineBarsData,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: hx.outlineVariant.withValues(alpha: 0.42),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: dates.length > 1,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, _) {
                      final index = value.round();
                      final middle = (dates.length - 1) ~/ 2;
                      if (index < 0 ||
                          index >= dates.length ||
                          (index != 0 &&
                              index != middle &&
                              index != dates.length - 1)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat('MMM d').format(dates[index]),
                          style: TextStyle(color: hx.secondary, fontSize: 10),
                        ),
                      );
                    },
                  ),
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
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map(
                        (spot) => LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)} kg',
                          TextStyle(
                            color: hx.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            duration: HxMotion.slow,
            curve: HxMotion.emphasized,
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
      error: (_, _) => const SizedBox.shrink(),
      data: (snapshot) {
        double maxRaw = 0;
        double maxAccommodating = 0;
        bool hasAccommodating = false;

        for (final resolved in snapshot.sets) {
          if (resolved.exercise.id != exerciseId ||
              isMachineAssistedPullup(resolved.exercise.slug)) {
            continue;
          }

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

        if (!hasAccommodating || maxRaw == 0 || maxAccommodating == 0) {
          return const SizedBox.shrink();
        }

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
                  const SizedBox(width: 10),
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
    final hx = context.hx;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              hx.primary.withValues(alpha: 0.12),
              hx.tertiary.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: hx.secondary),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
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
      error: (_, _) => const SizedBox.shrink(),
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

          sessionReps[day] = (sessionReps[day] ?? 0) + reps;

          if (isMachineAssistedPullup(resolved.exercise.slug)) continue;
          final e1rm =
              OneRepMax.estimate(
                weightKg: resolved.effectiveKg,
                reps: resolved.set.reps,
              ) ??
              resolved.effectiveKg;

          final isWeighted =
              resolved.equipmentVariant == 'weighted' ||
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
                  const SizedBox(width: 10),
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
  final LoggingMetric metric;
  final WeightFormat weightFormat;

  const ExerciseTimelineCard({
    super.key,
    required this.exerciseId,
    required this.metric,
    required this.weightFormat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(trainingSnapshotProvider);
    return snapshotAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (snapshot) {
        final sessions = <int, List<ResolvedSet>>{};
        for (final resolved in snapshot.sets) {
          if (resolved.exercise.id != exerciseId ||
              isMachineAssistedPullup(resolved.exercise.slug)) {
            continue;
          }
          sessions.putIfAbsent(resolved.session.id, () => []).add(resolved);
        }

        if (sessions.isEmpty) return const SizedBox.shrink();

        final recentSessions = sessions.entries.toList()
          ..sort((a, b) {
            final aDate =
                a.value.first.session.endedAt ??
                a.value.first.session.startedAt;
            final bDate =
                b.value.first.session.endedAt ??
                b.value.first.session.startedAt;
            return bDate.compareTo(aDate);
          });
        final latest = recentSessions.take(5).toList();
        final format = DateFormat('EEE, MMM d · HH:mm');
        final hx = context.hx;

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
              ...latest.map((entry) {
                final sessionSets = entry.value;
                final date =
                    sessionSets.first.session.endedAt ??
                    sessionSets.first.session.startedAt;
                final topSet = sessionSets.reduce(
                  (a, b) =>
                      _setScore(a, metric) >= _setScore(b, metric) ? a : b,
                );
                final summary = _sessionSummary(sessionSets, metric);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: hx.surfaceVariant.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: hx.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            Icons.fitness_center_rounded,
                            color: hx.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                format.format(date),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _TimelineMetricChip(
                                    label: '${sessionSets.length} sets',
                                  ),
                                  for (final value in summary)
                                    _TimelineMetricChip(label: value),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Top set · ${_setSummary(topSet, metric, weightFormat)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: hx.secondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  int _setScore(ResolvedSet set, LoggingMetric metric) {
    if (metric.has(SetField.duration)) return set.set.durationSeconds ?? 0;
    if (metric.has(SetField.distance)) {
      return ((set.set.distanceM ?? 0) * 1000).round();
    }
    if (metric.has(SetField.calories)) return set.set.calories ?? 0;
    if (metric.has(SetField.reps)) return set.countedReps;
    return (set.effectiveKg * 100).round();
  }

  List<String> _sessionSummary(List<ResolvedSet> sets, LoggingMetric metric) {
    final values = <String>[];
    if (metric.has(SetField.reps)) {
      final reps = sets.fold<int>(0, (sum, set) => sum + set.countedReps);
      if (reps > 0) values.add('$reps reps');
    }
    if (metric.isRepBased && metric.isLoaded) {
      final volume = sets.fold<double>(0, (sum, set) => sum + set.tonnageKg);
      if (volume > 0) values.add('Volume ${weightFormat.format(volume)}');
    }
    if (metric.has(SetField.duration)) {
      final seconds = sets.fold<int>(
        0,
        (sum, set) => sum + (set.set.durationSeconds ?? 0),
      );
      if (seconds > 0) values.add(_durationLabel(seconds));
    }
    if (metric.has(SetField.distance)) {
      final distance = sets.fold<double>(
        0,
        (sum, set) => sum + (set.set.distanceM ?? 0),
      );
      if (distance > 0) values.add('${distance.toStringAsFixed(0)} m');
    }
    if (metric.has(SetField.calories)) {
      final calories = sets.fold<int>(
        0,
        (sum, set) => sum + (set.set.calories ?? 0),
      );
      if (calories > 0) values.add('$calories kcal');
    }
    return values;
  }

  String _setSummary(
    ResolvedSet resolved,
    LoggingMetric metric,
    WeightFormat weightFormat,
  ) {
    final values = <String>[];
    if (metric.has(SetField.weight) && resolved.set.weightKg > 0) {
      final load = resolved.exercise.supportsWeightedBodyweight
          ? resolved.set.weightKg
          : resolved.effectiveKg;
      values.add(
        '${weightFormat.format(load)}${resolved.exercise.supportsWeightedBodyweight ? ' added' : ''}',
      );
    }
    if (metric.has(SetField.reps) && resolved.countedReps > 0) {
      values.add('${resolved.countedReps} reps');
    }
    if (metric.has(SetField.duration) && resolved.set.durationSeconds != null) {
      values.add(_durationLabel(resolved.set.durationSeconds!));
    }
    if (metric.has(SetField.distance) && resolved.set.distanceM != null) {
      values.add('${resolved.set.distanceM!.toStringAsFixed(0)} m');
    }
    if (metric.has(SetField.calories) && resolved.set.calories != null) {
      values.add('${resolved.set.calories} kcal');
    }
    return values.isEmpty ? 'Completed set' : values.join(' · ');
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) return '${remainder}s';
    if (remainder == 0) return '${minutes}m';
    return '${minutes}m ${remainder}s';
  }
}

class _TimelineMetricChip extends StatelessWidget {
  const _TimelineMetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            hx.primary.withValues(alpha: 0.14),
            hx.tertiary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: hx.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
