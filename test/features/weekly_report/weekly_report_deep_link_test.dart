import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_deep_link.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

NotificationAppLaunchDetails _details({
  required bool launched,
  String? payload,
}) => NotificationAppLaunchDetails(
  launched,
  notificationResponse: NotificationResponse(
    notificationResponseType: NotificationResponseType.selectedNotification,
    payload: payload,
  ),
);

void main() {
  group('WeeklyReportDeepLink.weekForTap', () {
    test('Sunday just after the fire time opens the week that just ended', () {
      expect(
        WeeklyReportDeepLink.weekForTap(
          now: DateTime(2026, 10, 4, 18, 1),
          timeHHMM: '18:00',
        ),
        const IsoWeek(2026, 40),
      );
    });

    test('Monday after the fire time still opens that week', () {
      expect(
        WeeklyReportDeepLink.weekForTap(
          now: DateTime(2026, 10, 5, 9),
          timeHHMM: '18:00',
        ),
        const IsoWeek(2026, 40),
      );
    });

    test('Sunday before the fire time opens the previous week', () {
      expect(
        WeeklyReportDeepLink.weekForTap(
          now: DateTime(2026, 10, 4, 17, 59),
          timeHHMM: '18:00',
        ),
        const IsoWeek(2026, 39),
      );
    });
  });

  group('WeeklyReportDeepLink.launchedByWeeklyReport', () {
    test('true for a launching weekly-report payload', () {
      expect(
        WeeklyReportDeepLink.launchedByWeeklyReport(
          _details(launched: true, payload: 'weekly_report'),
        ),
        isTrue,
      );
    });

    test('false for null details', () {
      expect(WeeklyReportDeepLink.launchedByWeeklyReport(null), isFalse);
    });

    test('false when the notification did not launch the app', () {
      expect(
        WeeklyReportDeepLink.launchedByWeeklyReport(
          _details(launched: false, payload: 'weekly_report'),
        ),
        isFalse,
      );
    });

    test('false for another payload or no response', () {
      expect(
        WeeklyReportDeepLink.launchedByWeeklyReport(
          _details(launched: true, payload: 'fasting_schedule:3'),
        ),
        isFalse,
      );
      expect(
        WeeklyReportDeepLink.launchedByWeeklyReport(
          const NotificationAppLaunchDetails(true),
        ),
        isFalse,
      );
    });
  });
}
