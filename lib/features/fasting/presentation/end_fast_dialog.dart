import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/in_app_notification_controller.dart';
import '../../../theme/colors.dart';
import '../../../theme/tokens/tokens.dart';
import '../../gamification/presentation/gamification_providers.dart';
import 'fasting_providers.dart';

/// Confirm-and-end flow for the active fasting session, shared by the fasting
/// sheet and the dashboard card so "End Fast" is reachable from the home
/// screen without opening the sheet.
void confirmEndFast(BuildContext context, WidgetRef ref) {
  final hx = context.hx;
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: hx.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("End Fast"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "What would you like to do with your active fasting session?",
              style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: AppColors.primary.withValues(alpha: 0.12),
              leading: Icon(Icons.check_circle_outline, color: AppColors.primary),
              title: Text(
                "Save",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "End fast and save session to history",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () async {
                Navigator.pop(dialogContext);
                final repo = ref.read(fastingRepositoryProvider);
                final active = await repo.activeSession();
                final pastSessions = await repo.watchHistory().first;
                await ref
                    .read(fastingNotificationSchedulerProvider)
                    .cancelFastingGoal();
                await repo.endSession(completed: true);
                if (active != null) {
                  final duration =
                      DateTime.now().difference(active.startedAt);
                  final evaluator = ref.read(achievementEvaluatorProvider);
                  final items = evaluator.evaluateFinishedFast(
                    fastDuration: duration,
                    pastSessions: pastSessions,
                    planName: 'Fasting Protocol',
                    targetSeconds: active.targetSeconds,
                  );
                  final notifier =
                      ref.read(inAppNotificationControllerProvider.notifier);
                  for (final item in items) {
                    notifier.show(item);
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: hx.surfaceContainer,
              leading: Icon(Icons.play_arrow_outlined, color: hx.onSurface),
              title: const Text(
                "Continue",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "Keep fast running",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () => Navigator.pop(dialogContext),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: Colors.red.withValues(alpha: 0.1),
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text(
                "Discard",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Delete session without saving",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () async {
                Navigator.pop(dialogContext);
                await ref
                    .read(fastingNotificationSchedulerProvider)
                    .cancelFastingGoal();
                final repo = ref.read(fastingRepositoryProvider);
                final active = await repo.activeSession();
                if (active != null) {
                  await repo.deleteSession(active.id);
                } else {
                  await repo.endSession(completed: false);
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

