import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('weekly report providers', () {
    late AppDatabase db;
    late FakeClock clock;
    late SharedPreferences prefs;
    late ProviderContainer container;

    Future<void> build({
      DateTime? now,
      Map<String, Object> initialPrefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(initialPrefs);
      prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      clock = FakeClock(now ?? DateTime(2026, 10, 5, 9));
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    }

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> enable({String time = '18:00'}) async {
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.setWeeklyReportEnabled(true);
      await notifier.setWeeklyReportTime(time);
    }

    WeeklyReportRepository repo() =>
        container.read(weeklyReportRepositoryProvider);

    Future<void> insert(IsoWeek week) =>
        repo().insertSnapshot(week: week, payloadVersion: 1, payloadJson: '{}');

    test('weeklyReportProvider emits null then the inserted record', () async {
      await build();
      final week = IsoWeek(2026, 40);
      final seen = <WeeklyReportRecord?>[];
      final sub = container.listen(
        weeklyReportProvider(week),
        (_, next) => seen.add(next.asData?.value),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await container.read(weeklyReportProvider(week).future);
      await insert(week);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen.whereType<WeeklyReportRecord>(), isNotEmpty);
      expect(
        container.read(weeklyReportProvider(week)).asData?.value?.week,
        week,
      );
    });

    test('equal IsoWeek instances share one provider', () async {
      await build();
      final a = weeklyReportProvider(IsoWeek(2026, 40));
      final b = weeklyReportProvider(IsoWeek(2026, 40));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('history emits newest week first', () async {
      await build();
      await insert(IsoWeek(2026, 38));
      await insert(IsoWeek(2026, 40));
      await insert(IsoWeek(2026, 39));

      final history = await container.read(weeklyReportHistoryProvider.future);

      expect(history.map((r) => r.week), [
        IsoWeek(2026, 40),
        IsoWeek(2026, 39),
        IsoWeek(2026, 38),
      ]);
    });

    test('enabled provider reflects the notification setting', () async {
      await build();
      expect(container.read(weeklyReportEnabledProvider), isFalse);
      await enable();
      expect(container.read(weeklyReportEnabledProvider), isTrue);
    });

    test('due week is null when the opt-in is off', () async {
      await build();
      expect(container.read(weeklyReportDueWeekProvider), isNull);
    });

    test('due week on Monday morning is the week that just ended', () async {
      await build(now: DateTime(2026, 10, 5, 9));
      await enable();
      expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 40));
    });

    test(
      'due week on Sunday before the trigger is the previous week',
      () async {
        await build(now: DateTime(2026, 10, 4, 17));
        await enable();
        expect(container.read(weeklyReportDueWeekProvider), IsoWeek(2026, 39));
      },
    );

    group('due week vs snapshot (WR-07)', () {
      test(
        'Sunday at the trigger: due week is the current, snapshot ok',
        () async {
          await build(now: DateTime(2026, 10, 4, 18));
          await enable();
          final due = container.read(weeklyReportDueWeekProvider);
          expect(due, IsoWeek(2026, 40));
          expect(due, IsoWeek.forNotificationTap(clock.now(), '18:00'));
          expect(
            container.read(weeklyReportServiceProvider).canSnapshot(due!),
            isTrue,
          );
          await container.read(weeklyReportProvider(due).future);
          expect(container.read(weeklyReportReadyProvider), due);
        },
      );

      test('Tuesday: due week is the previous, ended week', () async {
        await build(now: DateTime(2026, 9, 29, 10));
        await enable();
        final due = container.read(weeklyReportDueWeekProvider);
        expect(due, IsoWeek(2026, 39));
        expect(due, IsoWeek.forNotificationTap(clock.now(), '18:00'));
        expect(
          container.read(weeklyReportServiceProvider).canSnapshot(due!),
          isTrue,
        );
        await container.read(weeklyReportProvider(due).future);
        expect(container.read(weeklyReportReadyProvider), due);
        expect(
          container
              .read(weeklyReportServiceProvider)
              .canSnapshot(IsoWeek(2026, 40)),
          isFalse,
        );
      });
    });

    group('weeklyReportReadyProvider', () {
      Future<IsoWeek?> ready() async {
        // Let the week stream resolve before reading the derived value.
        final due = container.read(weeklyReportDueWeekProvider);
        if (due != null) {
          await container.read(weeklyReportProvider(due).future);
        }
        return container.read(weeklyReportReadyProvider);
      }

      test('disabled -> null', () async {
        await build();
        expect(await ready(), isNull);
      });

      test('enabled, due week without a row -> that week', () async {
        await build();
        await enable();
        expect(await ready(), IsoWeek(2026, 40));
      });

      test('enabled, unviewed row -> that week', () async {
        await build();
        await enable();
        await insert(IsoWeek(2026, 40));
        expect(await ready(), IsoWeek(2026, 40));
      });

      test('viewed row -> null', () async {
        await build();
        await enable();
        await insert(IsoWeek(2026, 40));
        await repo().markViewed(IsoWeek(2026, 40));
        expect(await ready(), isNull);
      });

      test('dismissed-empty marker for the due week -> null', () async {
        await build(initialPrefs: {'weekly_report_dismissed_week': '2026-40'});
        await enable();
        expect(container.read(weeklyReportDismissedWeekProvider), '2026-40');
        expect(await ready(), isNull);
      });

      test('a marker for another week does not hide the due week', () async {
        await build(initialPrefs: {'weekly_report_dismissed_week': '2026-39'});
        await enable();
        expect(await ready(), IsoWeek(2026, 40));
      });
    });
  });
}
