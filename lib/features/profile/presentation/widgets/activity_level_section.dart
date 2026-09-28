import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/activity_reset_policy.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Profile ActivityLevel picker: caption, tiles, and the reset flow.
///
/// While the estimate is still calibrating, a pick is the seed and saves
/// immediately (D-13). Once calibrated, a different pick is a manual reset:
/// it asks first (D-14) and then reports whether the estimate stays measured
/// (D-15). The reset is only the existing profile save, passed in as
/// [onChanged]; this widget never touches estimate history.
class ActivityLevelSection extends ConsumerWidget {
  const ActivityLevelSection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ActivityLevel selected;
  final ValueChanged<ActivityLevel> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestTdeeEstimateProvider).asData?.value;
    final calibrated = ActivityResetPolicy.isCalibrated(latest);
    final measured = ActivityResetPolicy.isMeasured(latest);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ActivityResetPolicy.caption(calibrated: calibrated),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: context.hx.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Column(
          children: ActivityLevel.values.map((a) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActivityTile(
                level: a,
                selected: a == selected,
                onTap: () => _onTap(
                  context,
                  a,
                  calibrated: calibrated,
                  measured: measured,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _onTap(
    BuildContext context,
    ActivityLevel a, {
    required bool calibrated,
    required bool measured,
  }) async {
    final action = ActivityResetPolicy.actionFor(
      isSameLevel: a == selected,
      calibrated: calibrated,
    );
    switch (action) {
      case ActivityResetAction.none:
        return;
      case ActivityResetAction.saveNow:
        onChanged(a);
        _showSaved(context, measured: false);
      case ActivityResetAction.confirm:
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(ActivityResetPolicy.dialogTitle),
            content: const Text(ActivityResetPolicy.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(ActivityResetPolicy.keepLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(ActivityResetPolicy.resetLabel),
              ),
            ],
          ),
        );
        if (result != true || !context.mounted) return;
        onChanged(a);
        _showSaved(context, measured: measured);
    }
  }

  void _showSaved(BuildContext context, {required bool measured}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ActivityResetPolicy.snackbar(measured: measured))),
    );
  }
}

// ── Activity level tile ───────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  final ActivityLevel level;
  final bool selected;
  final VoidCallback onTap;
  const _ActivityTile({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  static const _icons = {
    ActivityLevel.sedentary: Icons.weekend_rounded,
    ActivityLevel.lightlyActive: Icons.directions_walk_rounded,
    ActivityLevel.active: Icons.directions_run_rounded,
    ActivityLevel.veryActive: Icons.bolt_rounded,
  };

  static const _descriptions = {
    ActivityLevel.sedentary: 'Desk job, little or no exercise',
    ActivityLevel.lightlyActive: 'Light exercise 1–3 days/week',
    ActivityLevel.active: 'Moderate exercise 3–5 days/week',
    ActivityLevel.veryActive: 'Hard training 6–7 days/week',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? context.hx.primary.withValues(alpha: 0.1)
              : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? context.hx.primary
                : context.hx.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? context.hx.primary
                    : context.hx.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icons[level]!,
                size: 20,
                color: selected ? Colors.white : context.hx.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? context.hx.primary : null,
                    ),
                  ),
                  Text(
                    _descriptions[level]!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? context.hx.primary : context.hx.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
