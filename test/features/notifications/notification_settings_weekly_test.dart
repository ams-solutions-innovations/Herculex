import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';

void main() {
  group('NotificationSettings weekly report fields', () {
    test('defaults are opt-in off at 18:00', () {
      const s = NotificationSettings();
      expect(s.weeklyReportEnabled, isFalse);
      expect(s.weeklyReportTimeHHMM, '18:00');
    });

    test('copyWith changes only the weekly report fields', () {
      const base = NotificationSettings();
      final next = base.copyWith(
        weeklyReportEnabled: true,
        weeklyReportTimeHHMM: '19:30',
      );
      expect(next.weeklyReportEnabled, isTrue);
      expect(next.weeklyReportTimeHHMM, '19:30');
      expect(next.dailyLogReminderEnabled, base.dailyLogReminderEnabled);
      expect(next.dailyLogTimeHHMM, base.dailyLogTimeHHMM);
      expect(next.mealRemindersEnabled, base.mealRemindersEnabled);
    });

    test('toJson then fromJson round-trips both values', () {
      const s = NotificationSettings(
        weeklyReportEnabled: true,
        weeklyReportTimeHHMM: '07:45',
      );
      final json = s.toJson();
      expect(json['weeklyReportEnabled'], true);
      expect(json['weeklyReportTimeHHMM'], '07:45');

      final back = NotificationSettings.fromJson(json);
      expect(back.weeklyReportEnabled, isTrue);
      expect(back.weeklyReportTimeHHMM, '07:45');

      final viaRaw = NotificationSettings.fromRawJson(s.toRawJson());
      expect(viaRaw.weeklyReportEnabled, isTrue);
      expect(viaRaw.weeklyReportTimeHHMM, '07:45');
    });

    test('an old blob lacking both keys loads with defaults', () {
      final old = <String, dynamic>{
        'mealRemindersEnabled': false,
        'dailyLogReminderEnabled': true,
        'dailyLogTimeHHMM': '20:00',
      };
      final s = NotificationSettings.fromJson(old);
      expect(s.weeklyReportEnabled, isFalse);
      expect(s.weeklyReportTimeHHMM, '18:00');
      expect(s.dailyLogReminderEnabled, isTrue);
    });

    test('wrong-typed values fall back to defaults instead of throwing', () {
      final s = NotificationSettings.fromJson(<String, dynamic>{
        'weeklyReportEnabled': 'yes',
        'weeklyReportTimeHHMM': 1800,
      });
      expect(s.weeklyReportEnabled, isFalse);
      expect(s.weeklyReportTimeHHMM, '18:00');
    });
  });
}
