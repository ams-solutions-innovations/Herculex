import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:intl/intl.dart';

/// Past Dream Physique analyses, newest first. Text/metrics only — source
/// photos are deliberately never persisted (see
/// [DreamPhysiqueSummaryRepository]), so there is nothing visual to show.
class DreamPhysiqueHistoryView extends ConsumerWidget {
  const DreamPhysiqueHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history =
        ref.watch(dreamPhysiqueSummaryHistoryProvider).valueOrNull ??
        const <DreamPhysiqueAnalysisSummary>[];

    return HxScreenShell(
      title: 'Dream Physique History',
      children: [
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 64,
                  color: context.hx.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No past analyses yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.hx.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Run a Dream Physique analysis and it will show up here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.hx.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          )
        else
          for (final summary in history) ...[
            _HistoryEntryCard(summary: summary),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  final DreamPhysiqueAnalysisSummary summary;

  const _HistoryEntryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMd().format(summary.analyzedAt.toLocal());
    final weightChangeLabel = summary.weightChangeKg == 0
        ? 'little scale-weight change'
        : '${summary.weightChangeKg > 0 ? '+' : ''}'
              '${summary.weightChangeKg.toStringAsFixed(1)} kg';

    return HxCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.targetAestheticStyle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.hx.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary.timeframeRange,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.hx.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Stat(
                label: 'Current BF',
                value: '${summary.currentEstimatedBf.toStringAsFixed(0)}%',
              ),
              _Stat(
                label: 'Target BF',
                value: '${summary.targetBfPercent.toStringAsFixed(0)}%',
              ),
              _Stat(label: 'Weight change', value: weightChangeLabel),
              _Stat(
                label: 'Estimate',
                value: '${summary.estimatedMonths} months',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.hx.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
