import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/units.dart';
import '../../../theme/colors.dart';
import '../data/analytics_repository.dart';
import 'analytics_providers.dart';
import 'cns_recovery_cards.dart';

class InsightsView extends ConsumerWidget {
  const InsightsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          children: [
            Row(
              children: [
                if (Navigator.of(context).canPop()) ...[
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text('Insights', style: theme.textTheme.displayMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Dynamic performance analytics, biometric sleep vs. stress correlations, and targeted muscle recovery calculations.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 24),
            const RecoveryDetailCard(),
            const SizedBox(height: 24),
            const CnsTrendCard(),
            const SizedBox(height: 24),
            const _BalanceCard(),
            const SizedBox(height: 24),
            const _TonnageCard(),
            const SizedBox(height: 24),
            const _OneRmCard(),
            const SizedBox(height: 24),
            const _SleepVsRpeCard(),
            const SizedBox(height: 24),
            const _HrVsTonnageCard(),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(pushPullBalanceProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Push / Pull Volume', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Total set volume tagged by movement mechanics (last 4 weeks)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 24),
          balanceAsync.when(
            data: (res) => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("PUSH: ${res.pushPercentage.round()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("PULL: ${res.pullPercentage.round()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        Expanded(
                          flex: res.pushPercentage.round(),
                          child: Container(color: AppColors.primary),
                        ),
                        Expanded(
                          flex: res.pullPercentage.round(),
                          child: Container(color: AppColors.primaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
                if (res.hasAsymmetry) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: theme.colorScheme.secondary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Asymmetry detected (>25%). Consider adding more pulling exercises to support structural shoulder balance.",
                            style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

class _SleepVsRpeCard extends ConsumerWidget {
  const _SleepVsRpeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(sleepVsRpeProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sleep vs. Gym RPE', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                onPressed: () => _showMethodologyDialog(context, "Sleep vs. RPE Correlation",
                    "R² (Coefficient of Determination) indicates the percentage of variation in perceived session RPE that can be explained by sleep duration. A higher R² indicates that sleep heavily impacts recovery stress levels."),
              ),
            ],
          ),
          Text('Sleep duration hours (X) vs. average session RPE (Y)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 24),
          async.when(
            data: (res) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    height: 180,
                    child: ScatterChart(
                      ScatterChartData(
                        scatterSpots: res.points
                            .map((p) => ScatterSpot(
                                  p.x,
                                  p.y,
                                  dotPainter: FlDotCirclePainter(
                                    radius: 6,
                                    color: AppColors.primary,
                                  ),
                                ))
                            .toList(),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("R² FIT INDEX: ${res.r2.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        res.interpretation,
                        textAlign: TextAlign.end,
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

class _HrVsTonnageCard extends ConsumerWidget {
  const _HrVsTonnageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(hrVsTonnageProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Resting HR vs. Tonnage', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                onPressed: () => _showMethodologyDialog(context, "Resting HR vs. Tonnage Correlation",
                    "Elevated resting heart rate indicates systemic stress. This scatter plot tracks whether higher heart rates correlate with decreased absolute session volume (tonnage)."),
              ),
            ],
          ),
          Text('Resting HR bpm (X) vs. session tonnage kg (Y)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 24),
          async.when(
            data: (res) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    height: 180,
                    child: ScatterChart(
                      ScatterChartData(
                        scatterSpots: res.points
                            .map((p) => ScatterSpot(
                                  p.x,
                                  p.y,
                                  dotPainter: FlDotCirclePainter(
                                    radius: 6,
                                    color: Colors.teal,
                                  ),
                                ))
                            .toList(),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("R² FIT INDEX: ${res.r2.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        res.interpretation,
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

void _showMethodologyDialog(BuildContext context, String title, String description) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CLOSE", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    },
  );
}

class _TonnageCard extends ConsumerWidget {
  const _TonnageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(weeklyTonnageProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly tonnage', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Total kg moved per week (working sets only)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: async.when(
              data: (data) => _emptyOrChart(data, theme),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyOrChart(List<WeeklyTonnage> data, ThemeData theme) {
    if (data.every((w) => w.tonnageKg == 0)) {
      return Center(
        child: Text('Log a workout to see your tonnage.', style: theme.textTheme.bodyMedium),
      );
    }
    final maxY = data.map((d) => d.tonnageKg).fold<double>(0, (a, b) => b > a ? b : a);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                if (i % 2 != data.length % 2) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M/d').format(data[i].weekStart),
                    style: TextStyle(color: AppColors.secondary, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].tonnageKg,
                color: AppColors.primary,
                width: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }
}

class _OneRmCard extends ConsumerWidget {
  const _OneRmCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(topOneRmsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated 1RM', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Top lifts, projected from best working set (Epley + Brzycki avg)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 16),
          async.when(
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No completed sets yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : Column(
                    children: [
                      for (final p in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(p.exerciseName, style: theme.textTheme.titleSmall),
                              ),
                              Text(
                                ref.watch(weightFormatProvider).format(p.estimatedOneRmKg),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}