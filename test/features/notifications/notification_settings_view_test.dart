import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NotificationSettingsView renders all sections and toggles', (tester) async {
    tester.view.physicalSize = const Size(1080, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: NotificationSettingsView(),
        ),
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
}
