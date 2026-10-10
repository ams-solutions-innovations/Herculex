import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/app.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> boot(WidgetTester tester) async {
    // Tall enough for every step; wide because the test font runs wider than
    // the real one and would overflow the existing two-button rows.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const HerculexApp(),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The last tap leaves onboarding for the app shell, whose ambient
  /// animations never settle.
  Future<void> tapAndLeave(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Profile? savedProfile(SharedPreferences prefs) {
    final raw = prefs.getString('herculex.profile');
    return raw == null ? null : Profile.decode(raw);
  }

  testWidgets('the strength check is saved and sets the starting band', (
    tester,
  ) async {
    final prefs = await boot(tester);

    await tapText(tester, 'Muscle Gain');
    await tapText(tester, 'Next');
    await tapText(tester, 'Active');
    await tapText(tester, 'Next');
    await tester.enterText(find.widgetWithText(TextField, 'e.g. 65'), '80');
    await tapText(tester, 'Next');

    expect(find.text('What can you lift?'), findsOneWidget);
    expect(find.text("You'll start at Novice"), findsOneWidget);

    // Bench is the second barbell row; muscle-ups the last reps field.
    await tester.enterText(find.widgetWithText(TextField, 'kg').at(1), '140');
    await tester.enterText(find.widgetWithText(TextField, 'reps').at(1), '1');
    final muscleUps = find.widgetWithText(TextField, 'reps').last;
    await tester.ensureVisible(muscleUps);
    await tester.enterText(muscleUps, '3');
    await tester.pumpAndSettle();

    expect(find.text("You'll start at Advanced"), findsOneWidget);

    await tapAndLeave(tester, 'Complete');

    final survey = savedProfile(prefs)?.strengthSurvey;
    expect(survey, isNotNull);
    expect(survey!.lifts[StrengthLift.bench]?.weightKg, 140);
    expect(survey.lifts[StrengthLift.muscleUp]?.reps, 3);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('skipping onboarding saves a profile without a survey', (
    tester,
  ) async {
    final prefs = await boot(tester);

    await tapAndLeave(tester, 'Skip');

    final profile = savedProfile(prefs);
    expect(profile, isNotNull);
    expect(profile!.strengthSurvey, isNull);

    await tester.pump(const Duration(seconds: 3));
  });
}
