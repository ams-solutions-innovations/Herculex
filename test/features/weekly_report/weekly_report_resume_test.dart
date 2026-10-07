import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_resume.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('weeklyReportResumeProvider', () {
    late AppDatabase db;
    late FakeClock clock;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      // Sunday 4 Oct 2026, 17:00: the 18:00 trigger has not fired yet.
      clock = FakeClock(DateTime(2026, 10, 4, 17));
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.setWeeklyReportEnabled(true);
      await notifier.setWeeklyReportTime('18:00');
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    void resume() => TestWidgetsFlutterBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    test('a resume after the Sunday trigger moves the due week', () {
      container.read(weeklyReportResumeProvider);
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 39));

      clock.set(DateTime(2026, 10, 4, 18, 30));
      // Not re-evaluated on its own.
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 39));

      resume();
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 40));
    });

    test('other lifecycle states do not re-evaluate', () {
      container.read(weeklyReportResumeProvider);
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 39));
      clock.set(DateTime(2026, 10, 4, 18, 30));

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 39));
      // Leave the binding in the foreground state for the next test.
      resume();
    });

    test('disposing the container removes the observer', () {
      container.read(weeklyReportResumeProvider);
      container.dispose();
      // Would throw if a disposed container were still invalidated.
      resume();
    });
  });
}
