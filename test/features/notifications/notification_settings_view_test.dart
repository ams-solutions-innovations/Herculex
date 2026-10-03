import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NotificationSettingsView renders all sections and toggles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: NotificationSettingsView()),
      ),
    );

    await tester.pumpAndSettle();

    // Verify AppBar and section titles
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('MEALS'), findsOneWidget);
    expect(find.text('FASTING'), findsOneWidget);
    expect(find.text('SUPPLEMENTS'), findsOneWidget);
    expect(find.text('WORKOUTS'), findsOneWidget);
    expect(find.text('DAILY HABITS & LOG'), findsOneWidget);

    // Verify switches and labels
    expect(find.text('Meal Reminders'), findsOneWidget);
    expect(find.text('Fasting Goal Reached'), findsOneWidget);
    expect(find.text('Fasting Schedule Reminders'), findsOneWidget);
    expect(find.text('Daily Supplement Reminders'), findsOneWidget);
    expect(find.text('Post-Workout Supplements'), findsOneWidget);
    expect(find.text('Live Workout Notification'), findsOneWidget);
    expect(find.text('Rest Timer Alerts'), findsOneWidget);
    expect(find.text('Evening Log Reminder'), findsOneWidget);

    // Verify default meals shown
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Snacks'), findsOneWidget);
  });

  group('Weekly report toggle', () {
    late SharedPreferences prefs;

    Future<ProviderContainer> pumpView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotificationSettingsView()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    final tile = find.ancestor(
      of: find.text('Weekly report'),
      matching: find.byType(Row),
    );

    testWidgets('shows an off switch with the schedule and AI disclosure', (
      tester,
    ) async {
      final container = await pumpView(tester);

      expect(find.text('Weekly report'), findsOneWidget);
      expect(
        container.read(notificationSettingsProvider).weeklyReportEnabled,
        isFalse,
      );
      final sw = tester.widget<Switch>(
        find.descendant(of: tile.first, matching: find.byType(Switch)),
      );
      expect(sw.value, isFalse);
      expect(find.textContaining('Sundays at 18:00.'), findsOneWidget);
      expect(find.textContaining('Herculex AI'), findsOneWidget);
      expect(find.textContaining('powered by Google Gemini'), findsOneWidget);
      expect(find.text('Report Time'), findsNothing);
    });

    testWidgets('turning it on reveals the time row and persists', (
      tester,
    ) async {
      final container = await pumpView(tester);

      await tester.tap(
        find.descendant(of: tile.first, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(notificationSettingsProvider).weeklyReportEnabled,
        isTrue,
      );
      expect(find.text('Report Time'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
    });

    testWidgets('tapping the time row opens the picker; a new time shows in '
        'the subtitle', (tester) async {
      final container = await pumpView(tester);
      await container
          .read(notificationSettingsProvider.notifier)
          .setWeeklyReportEnabled(true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Confirming without changing keeps the stored time.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(
        container.read(notificationSettingsProvider).weeklyReportTimeHHMM,
        '18:00',
      );

      await container
          .read(notificationSettingsProvider.notifier)
          .setWeeklyReportTime('19:30');
      await tester.pumpAndSettle();
      expect(find.textContaining('Sundays at 19:30.'), findsOneWidget);
      expect(find.text('19:30'), findsOneWidget);
    });

    testWidgets('turning it off hides the time row', (tester) async {
      final container = await pumpView(tester);
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.setWeeklyReportEnabled(true);
      await tester.pumpAndSettle();
      expect(find.text('Report Time'), findsOneWidget);

      await tester.tap(
        find.descendant(of: tile.first, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report Time'), findsNothing);
      expect(
        container.read(notificationSettingsProvider).weeklyReportEnabled,
        isFalse,
      );
    });
  });
}
