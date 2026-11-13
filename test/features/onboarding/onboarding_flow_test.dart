import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/onboarding/presentation/views/onboarding_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const OnboardingView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('welcome offers the three ways in', (tester) async {
    await _pump(tester);

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign up with email'), findsOneWidget);
  });

  testWidgets('without an account: intro, then goal step gates on a choice', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Continue without an account'));
    await tester.pumpAndSettle();
    expect(find.text('Every set, logged in seconds.'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pick the body you are building.'), findsOneWidget);

    await tester.tap(find.text('Set up my profile'));
    await tester.pumpAndSettle();
    expect(find.text('What is your primary goal?'), findsOneWidget);

    // Next is disabled until a goal is picked.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What is your primary goal?'), findsOneWidget);

    await tester.tap(find.text('Muscle Gain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about yourself'), findsOneWidget);
  });

  testWidgets('Skip intro jumps straight to the goal step', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Continue without an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('What is your primary goal?'), findsOneWidget);
  });
}
