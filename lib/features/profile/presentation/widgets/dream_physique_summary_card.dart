import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';

class DreamPhysiqueSummaryCard extends ConsumerWidget {
  const DreamPhysiqueSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(dreamPhysiqueSummaryProvider).valueOrNull;
    final hasSummary = summary != null;
    final subtitle = hasSummary
        ? '${summary.targetAestheticStyle} · ${summary.timeframeRange}'
        : 'Set a target physique and get an estimated roadmap.';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.hx.primary.withValues(alpha: 0.12),
            context.hx.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hx.primary.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('dream-physique-summary-card'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(AppRoutes.dreamPhysique),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 22,
                    color: context.hx.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hasSummary
                                ? 'Dream Physique saved'
                                : 'Dream Physique AI',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.hx.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (hasSummary) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Estimated ${summary.estimatedMonths} months · '
                          'target ${summary.targetBfPercent.toStringAsFixed(0)}% BF',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: context.hx.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to start a new analysis.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: context.hx.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.hx.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
