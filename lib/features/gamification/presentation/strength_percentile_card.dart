import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/gamification/domain/strength_percentiles.dart';
import 'package:herculex/features/gamification/presentation/level_band_style.dart';

/// "How you compare": every logged benchmark lift as top-% of lifters, with
/// the rougher worldwide estimate beside it. Hidden until a lift is logged.
class StrengthPercentileCard extends ConsumerWidget {
  const StrengthPercentileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(strengthPercentilesProvider).valueOrNull;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hx = context.hx;

    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x5),
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How you compare',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: HxSpace.x1),
            Text(
              'From your logged best sets. Worldwide is a rough estimate '
              'that counts people who never train the lift.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hx.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HxSpace.x4),
            for (final p in all) _PercentileRow(p: p),
          ],
        ),
      ),
    );
  }
}

class _PercentileRow extends StatelessWidget {
  const _PercentileRow({required this.p});

  final LiftPercentile p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    // A bar that fills as the top-% shrinks.
    final fill = (1 - p.lifterTopPct / 100).clamp(0.02, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.lift.label} · ${formatStrengthValue(p.lift, p.value)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Top ${formatTopPct(p.lifterTopPct)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: hx.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          ClipRRect(
            borderRadius: BorderRadius.circular(HxRadius.pill),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: 6,
              backgroundColor: hx.surfaceVariant.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(hx.primary),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'of lifters · top ${formatTopPct(p.worldTopPct)} worldwide (est.)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
