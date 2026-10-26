import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_history.dart';

/// Full-page dedicated view for browsing, managing, and reviewing past fasting sessions.
class FastingHistoryView extends StatelessWidget {
  const FastingHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return const HxScreenShell(
      title: 'Fasting History',
      children: [
        FastingHistory(
          showAll: true,
          showHeader: false,
        ),
      ],
    );
  }
}
