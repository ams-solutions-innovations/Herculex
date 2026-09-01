import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/hercul/application/hercul_providers.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';

class HerculInsightsCard extends ConsumerWidget {
  const HerculInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messagesAsync = ref.watch(herculMessagesProvider);

    return dashboardCard(
      accent: context.hx.primary,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 20,
                  color: context.hx.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hercul Insights',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          messagesAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    "You're fully on track. No coaching notes today.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.hx.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                );
              }

              return Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < messages.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _MessageTile(message: messages[i]),
                      ],
                    ],
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, st) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load insights.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends ConsumerWidget {
  final HerculMessage message;

  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cta = message.cta;

    IconData icon;
    Color iconColor;

    switch (message.domain) {
      case HerculDomain.recovery:
        icon = Icons.battery_charging_full;
        iconColor = context.hx.warning;
        break;
      case HerculDomain.volume:
        icon = Icons.bar_chart;
        iconColor = context.hx.domainTraining;
        break;
      case HerculDomain.nutrition:
        icon = Icons.restaurant;
        iconColor = context.hx.domainNutrition;
        break;
      case HerculDomain.bodyweight:
        icon = Icons.monitor_weight_outlined;
        iconColor = context.hx.domainRecovery;
        break;
      case HerculDomain.consistency:
        icon = Icons.calendar_month;
        iconColor = context.hx.primary;
        break;
      case HerculDomain.ergonomics:
        icon = Icons.accessibility_new;
        iconColor = context.hx.domainFasting;
        break;
    }

    return InkWell(
      onTap: cta == null
          ? null
          : () {
              if (cta.type == 'route') {
                context.push(cta.value);
              } else if (cta.type == 'substitute') {
                // Future implementation for substitutions
              }
              ref.read(herculLogFiredProvider)(message.ruleId);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  if (cta != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      cta.type == 'route' ? 'Review →' : 'Take Action',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: context.hx.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
