import 'package:flutter/material.dart';

import 'macro_trend_view.dart';

export 'macro_trend_view.dart';

/// Calorie-trends page behind the dashboard's avg-intake banner.
/// Delegates to [MacroTrendView] with `macro: 'kcal'`.
class WeeklyCaloriesView extends StatelessWidget {
  const WeeklyCaloriesView({super.key});

  @override
  Widget build(BuildContext context) {
    return const MacroTrendView(macro: 'kcal');
  }
}
