import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';

/// Presentational, visible notice for a program slot the deterministic
/// planner left empty because no safe candidate qualified (Phase 17, D-04).
///
/// The message shown is always exactly [reason] — the planner (Wave 3)
/// already generates the human-readable rationale and this widget must not
/// re-derive or duplicate it. [pattern] is accepted only for an optional
/// icon/accessibility label, never for deriving the displayed text.
class EmptySlotNotice extends StatelessWidget {
  const EmptySlotNotice({super.key, this.pattern, required this.reason});

  final String? pattern;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: pattern == null ? null : 'Empty slot: $pattern',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(reason, style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
