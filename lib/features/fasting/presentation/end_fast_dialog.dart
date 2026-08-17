import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import 'fasting_providers.dart';

/// Confirm-and-end flow for the active fasting session, shared by the fasting
/// sheet and the dashboard card so "End Fast" is reachable from the home
/// screen without opening the sheet.
void confirmEndFast(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text("End Fast"),
        content: const Text(
          "Are you sure you want to end your current fasting session?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref
                  .read(fastingNotificationSchedulerProvider)
                  .cancelFastingGoal();
              await ref
                  .read(fastingRepositoryProvider)
                  .endSession(completed: true);
            },
            child: Text(
              "END FAST",
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
