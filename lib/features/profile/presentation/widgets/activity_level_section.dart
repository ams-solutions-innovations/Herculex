import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/hx_picker.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/activity_reset_policy.dart';
import 'package:herculex/features/nutrition/presentation/widgets/tdee_estimate_badge.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Icon and one-line description for each [ActivityLevel], shared by the
/// Profile row and the calibration page's "change level" picker.
const Map<ActivityLevel, IconData> activityLevelIcons = {
  ActivityLevel.sedentary: Icons.weekend_rounded,
  ActivityLevel.lightlyActive: Icons.directions_walk_rounded,
  ActivityLevel.active: Icons.directions_run_rounded,
  ActivityLevel.veryActive: Icons.bolt_rounded,
};

const Map<ActivityLevel, String> activityLevelDescriptions = {
  ActivityLevel.sedentary: 'Desk job, little or no exercise',
  ActivityLevel.lightlyActive: 'Light exercise 1–3 days/week',
  ActivityLevel.active: 'Moderate exercise 3–5 days/week',
  ActivityLevel.veryActive: 'Hard training 6–7 days/week',
};

/// Profile ActivityLevel row: the chosen level, a calibration badge and the
/// reset flow.
///
/// Tapping the row opens a bottom-sheet picker; tapping the badge opens the
/// calibration page that shows how the estimate is worked out.
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
        _ActivityRow(
          level: selected,
          onTap: () => pickAndApplyActivityLevel(
            context,
            selected: selected,
            calibrated: calibrated,
            measured: measured,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        TdeeEstimateBadge(
          alignment: Alignment.center,
          onTap: () => context.push(AppRoutes.activityCalibration),
        ),
        const SizedBox(height: HxSpace.x1),
        Text(
          ActivityResetPolicy.caption(calibrated: calibrated),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: context.hx.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Opens the level picker and runs the chosen level through the reset policy:
/// nothing, save at once, or confirm first. Shared by the Profile row and the
/// calibration page so both behave identically.
Future<void> pickAndApplyActivityLevel(
  BuildContext context, {
  required ActivityLevel selected,
  required bool calibrated,
  required bool measured,
  required ValueChanged<ActivityLevel> onChanged,
}) async {
  final picked = await showHxPicker<ActivityLevel>(
    context,
    title: 'Activity level',
    subtitle: ActivityResetPolicy.caption(calibrated: calibrated),
    selected: selected,
    options: [
      for (final a in ActivityLevel.values)
        HxPickerOption(
          value: a,
          label: a.label,
          description: activityLevelDescriptions[a],
          icon: activityLevelIcons[a],
        ),
    ],
  );
  if (picked == null || !context.mounted) return;

  final action = ActivityResetPolicy.actionFor(
    isSameLevel: picked == selected,
    calibrated: calibrated,
  );
  switch (action) {
    case ActivityResetAction.none:
      return;
    case ActivityResetAction.saveNow:
      onChanged(picked);
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
      onChanged(picked);
      _showSaved(context, measured: measured);
  }
}

void _showSaved(BuildContext context, {required bool measured}) {
  AppNotice.show(context, ActivityResetPolicy.snackbar(measured: measured));
}

// ── Activity level row ────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.level, required this.onTap});

  final ActivityLevel level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    return Material(
      color: hx.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(activityLevelIcons[level], size: 22, color: hx.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Activity level',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                level.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hx.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: hx.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
