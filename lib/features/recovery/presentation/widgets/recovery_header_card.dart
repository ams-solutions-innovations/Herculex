import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';

/// Overall readiness plus a Recovered/Recovering/Fatigued tally across the
/// 19 muscle groups — the Recovery page's summary strip.
class RecoveryHeaderCard extends ConsumerWidget {
  const RecoveryHeaderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final cns = ref.watch(cnsTrendsProvider);
    final recovery = ref.watch(recoveryV3Provider);

    return HxCard(
      accent: hx.domainRecovery,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERALL READINESS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          cns.when(
            data: (t) => Text(
              '${(t.readiness * 100).round()}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: hx.domainRecovery,
              ),
            ),
            loading: () => const SizedBox(
              height: 32,
              width: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Text('—', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: HxSpace.x4),
          recovery.when(
            data: (groups) => Row(
              children: [
                Expanded(
                  child: _tally(
                    context,
                    count: groups.where((g) => g.status == 'RECOVERED').length,
                    label: 'Recovered',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _tally(
                    context,
                    count: groups.where((g) => g.status == 'RECOVERING').length,
                    label: 'Recovering',
                    color: Colors.amber,
                  ),
                ),
                Expanded(
                  child: _tally(
                    context,
                    count: groups.where((g) => g.status == 'FATIGUED').length,
                    label: 'Fatigued',
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _tally(
    BuildContext context, {
    required int count,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
        ),
      ],
    );
  }
}
