import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';

/// Calls [onResumed] when the app returns to the foreground.
class WeeklyReportResumeObserver with WidgetsBindingObserver {
  WeeklyReportResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

/// Keeps the dashboard "report ready" card honest across the Sunday trigger.
///
/// [weeklyReportDueWeekProvider] reads the clock when it is built, so an app
/// that stays open from Sunday afternoon into the evening would not notice the
/// 18:00 trigger passing. Re-evaluating it on every foreground resume makes the
/// card (and everything derived from the due week) catch up. Registered once
/// from `app.dart`; it only invalidates a read-only provider and never
/// generates a report or calls the backend.
final weeklyReportResumeProvider = Provider<void>((ref) {
  final observer = WeeklyReportResumeObserver(
    () => ref.invalidate(weeklyReportDueWeekProvider),
  );
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});
