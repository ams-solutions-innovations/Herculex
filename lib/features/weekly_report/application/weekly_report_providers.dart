import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_inputs_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_service.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

// NOTE: this file may import nutrition_providers.dart; nutrition must never
// import anything from weekly_report/application (that would be a cycle).

/// SharedPreferences key of the "this due week had no data, stop offering it"
/// marker (Pitfall 11). The value is [weeklyReportWeekKey] of that week.
const String weeklyReportDismissedWeekKey = 'weekly_report_dismissed_week';

/// Stable text id of a week for the dismissed marker, for example `2026-40`.
String weeklyReportWeekKey(IsoWeek week) => '${week.isoYear}-${week.isoWeek}';

final weeklyReportRepositoryProvider = Provider<WeeklyReportRepository>((ref) {
  return WeeklyReportRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  );
});

final weeklyReportInputsRepositoryProvider =
    Provider<WeeklyReportInputsRepository>((ref) {
      return WeeklyReportInputsRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(nutritionRepositoryProvider),
        ref.watch(tdeeEstimatesRepositoryProvider),
      );
    });

/// Snapshot and narrative service. The per-day target comes from the same
/// resolver the Today screen uses; a resolver error means "no target" for that
/// day rather than a failed report.
final weeklyReportServiceProvider = Provider<WeeklyReportService>((ref) {
  return WeeklyReportService(
    repository: ref.watch(weeklyReportRepositoryProvider),
    inputs: ref.watch(weeklyReportInputsRepositoryProvider),
    narrative: ref.watch(weeklyReportNarrativeServiceProvider),
    clock: ref.watch(clockProvider),
    targetForDay: (day) async {
      try {
        return await ref.read(effectiveTargetsProvider(day).future);
      } catch (_) {
        return null;
      }
    },
  );
});

/// One week's stored report, live. Null until the week has been opened (rows
/// are generated on open, not in the background).
final weeklyReportProvider =
    StreamProvider.family<WeeklyReportRecord?, IsoWeek>((ref, week) {
      return ref.watch(weeklyReportRepositoryProvider).watchWeek(week);
    });

/// Every stored report, newest week first.
final weeklyReportHistoryProvider = StreamProvider<List<WeeklyReportRecord>>((
  ref,
) {
  return ref.watch(weeklyReportRepositoryProvider).watchHistory();
});

/// The weekly report opt-in (D-07). Off by default.
final weeklyReportEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
    notificationSettingsProvider.select((s) => s.weeklyReportEnabled),
  );
});

/// The week the most recent Sunday-at-HH:MM trigger belongs to, or null while
/// the opt-in is off. Evaluated when the provider is (re)built; a new trigger
/// passing while the app stays open is picked up on the next rebuild.
final weeklyReportDueWeekProvider = Provider<IsoWeek?>((ref) {
  if (!ref.watch(weeklyReportEnabledProvider)) return null;
  final time = ref.watch(
    notificationSettingsProvider.select((s) => s.weeklyReportTimeHHMM),
  );
  return IsoWeek.forNotificationTap(ref.watch(clockProvider).now(), time);
});

/// [weeklyReportWeekKey] of the due week the user opened and found empty, or
/// null. Seeded from SharedPreferences so the dashboard card does not return
/// after a restart. Written by the report controller.
final weeklyReportDismissedWeekProvider = StateProvider<String?>((ref) {
  return ref
      .read(sharedPreferencesProvider)
      .getString(weeklyReportDismissedWeekKey);
});

/// The week the dashboard card should offer, or null (D-09, Pitfall 11).
///
/// A row only exists after the report was opened, so "ready" means: opt-in on,
/// a due week exists, it was not dismissed as empty, and there is either no row
/// yet or a row the user has not viewed. While the row is still loading the
/// answer is null, so the card does not flash for an already-viewed report.
final weeklyReportReadyProvider = Provider<IsoWeek?>((ref) {
  final due = ref.watch(weeklyReportDueWeekProvider);
  if (due == null) return null;
  if (ref.watch(weeklyReportDismissedWeekProvider) ==
      weeklyReportWeekKey(due)) {
    return null;
  }
  final row = ref.watch(weeklyReportProvider(due));
  if (row.isLoading || row.hasError) return null;
  final record = row.asData?.value;
  if (record == null || record.viewedAt == null) return due;
  return null;
});
