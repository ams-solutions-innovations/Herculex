import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';

/// Shared muscle-recovery bar row: name, progress bar, score, and two
/// optional trailing pieces (an ETA chip and a status dot) that the two
/// original call sites — `RecoverySummaryCard` and `RecoveryDetailCard` —
/// don't pass, so they render exactly as they did before this widget existed.
class MuscleRecoveryRow extends StatelessWidget {
  final String muscle;
  final int recoveryScore;

  /// Pre-formatted ETA text (e.g. "Recovered", "~18h", "10d+"). Null omits
  /// the chip — deliberately a string, not the raw hours: the caller decides
  /// how to phrase an already-recovered muscle, since "null ETA" and "no ETA
  /// requested" need different rendering and both would otherwise be `null`.
  final String? etaLabel;

  /// Small trailing status dot, e.g. a deload flag. Null omits it.
  final Color? statusDotColor;

  const MuscleRecoveryRow({
    super.key,
    required this.muscle,
    required this.recoveryScore,
    this.etaLabel,
    this.statusDotColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = recoveryScore >= 70
        ? Colors.green
        : recoveryScore >= 30
        ? Colors.amber
        : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              muscle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // Out-of-range values make the indicator paint outside its
                // own box; this is the only progress `value:` in the app that
                // wasn't clamped.
                value: (recoveryScore / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.outlineVariant.withValues(
                  alpha: 0.2,
                ),
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$recoveryScore',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          if (etaLabel != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                etaLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
          if (statusDotColor != null) ...[
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusDotColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
