import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/buddy/application/buddy_share_policy.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';

/// Segmented toggle button for choosing whether an exercise action applies to "Both" or "Only Me".
class BuddyScopeToggle extends StatelessWidget {
  const BuddyScopeToggle({
    super.key,
    required this.scope,
    required this.onChanged,
    this.decision,
  });

  final BuddyScope scope;
  final ValueChanged<BuddyScope> onChanged;
  final ShareDecision? decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForced = decision != null && !decision!.userOverridable;
    final forcedReason = decision?.reason;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<BuddyScope>(
                segments: const [
                  ButtonSegment<BuddyScope>(
                    value: BuddyScope.both,
                    label: Text('Both (Shared)'),
                    icon: Icon(Icons.group_rounded, size: 18),
                  ),
                  ButtonSegment<BuddyScope>(
                    value: BuddyScope.mine,
                    label: Text('Only Me'),
                    icon: Icon(Icons.person_rounded, size: 18),
                  ),
                ],
                selected: {scope},
                onSelectionChanged: isForced
                    ? null
                    : (selected) {
                        if (selected.isNotEmpty) {
                          onChanged(selected.first);
                        }
                      },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return AppColors.surfaceContainer.withValues(alpha: 0.5);
                    }
                    return null;
                  }),
                ),
              ),
            ),
          ],
        ),
        if (isForced && forcedReason != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  forcedReason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
