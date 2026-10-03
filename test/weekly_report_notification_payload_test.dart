import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_action_queue.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PendingWeeklyReportOpenQueue', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('is not pending on empty prefs', () {
      expect(PendingWeeklyReportOpenQueue.isPending(prefs), isFalse);
    });

    test('enqueue sets the flag and take clears it exactly once', () async {
      await PendingWeeklyReportOpenQueue.enqueue(prefs);
      expect(PendingWeeklyReportOpenQueue.isPending(prefs), isTrue);

      expect(await PendingWeeklyReportOpenQueue.take(prefs), isTrue);
      expect(PendingWeeklyReportOpenQueue.isPending(prefs), isFalse);
      expect(await PendingWeeklyReportOpenQueue.take(prefs), isFalse);
    });

    test('uses the documented prefs key', () {
      expect(
        PendingWeeklyReportOpenQueue.prefsKey,
        'pending_weekly_report_open',
      );
    });
  });

  group('dispatchWeeklyReportPayload', () {
    tearDown(() => WorkoutNotificationService.onWeeklyReportTap = null);

    test('invokes the callback once and returns true', () async {
      var calls = 0;
      WorkoutNotificationService.onWeeklyReportTap = () async => calls++;

      final handled =
          await WorkoutNotificationService.dispatchWeeklyReportPayload(
            'weekly_report',
          );

      expect(handled, isTrue);
      expect(calls, 1);
    });

    test('returns true without throwing when no callback is set', () async {
      WorkoutNotificationService.onWeeklyReportTap = null;
      expect(
        await WorkoutNotificationService.dispatchWeeklyReportPayload(
          'weekly_report',
        ),
        isTrue,
      );
    });

    test('ignores other payloads and invokes nothing', () async {
      var calls = 0;
      WorkoutNotificationService.onWeeklyReportTap = () async => calls++;

      for (final payload in <String?>[
        null,
        '',
        'fasting_schedule:3',
        'workout:1:2',
      ]) {
        expect(
          await WorkoutNotificationService.dispatchWeeklyReportPayload(payload),
          isFalse,
          reason: 'payload: $payload',
        );
      }
      expect(calls, 0);
    });
  });

  group('handleWeeklyReportBackgroundTap', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('queues the open flag for the weekly payload, no actionId needed', () async {
      final handled = await handleWeeklyReportBackgroundTap(
        'weekly_report',
        prefs,
      );
      expect(handled, isTrue);
      expect(PendingWeeklyReportOpenQueue.isPending(prefs), isTrue);
    });

    test('does nothing for other payloads', () async {
      for (final payload in <String?>[null, '', 'fasting_schedule:3']) {
        expect(await handleWeeklyReportBackgroundTap(payload, prefs), isFalse);
      }
      expect(PendingWeeklyReportOpenQueue.isPending(prefs), isFalse);
    });
  });
}
