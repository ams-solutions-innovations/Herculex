import 'package:flutter/material.dart';

import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/components/premium_text_field.dart';

class AdminInsertWorkoutView extends StatelessWidget {
  const AdminInsertWorkoutView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("New Workout", style: theme.textTheme.labelLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text("Create Exercise", style: theme.textTheme.displayMedium),
          const SizedBox(height: 32),
          const PremiumTextField(hintText: "Exercise Name (e.g. Hex Press)"),
          const SizedBox(height: 16),
          const PremiumTextField(
            hintText: "Biomechanical Tags (comma separated)",
          ),
          const SizedBox(height: 16),
          const PremiumTextField(hintText: "Target Muscles"),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: PremiumTextField(hintText: "Sets")),
              SizedBox(width: 16),
              Expanded(child: PremiumTextField(hintText: "Reps")),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: PremiumButton(
              text: "Save Workout",
              onTap: () {
                AppNotice.show(
                  context,
                  "Workout saved (stub — persistence lands in Phase 2)",
                );
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
