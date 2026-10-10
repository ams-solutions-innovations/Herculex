import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/settings/presentation/account_settings_view.dart';
import 'package:herculex/features/settings/presentation/appearance_settings_view.dart';
import 'package:herculex/features/settings/presentation/data_library_settings_view.dart';
import 'package:herculex/features/settings/presentation/permissions_settings_view.dart';
import 'package:herculex/features/settings/presentation/preferences_settings_view.dart';
import 'package:herculex/features/settings/presentation/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = Profile(
  goal: FitnessGoal.maintenance,
  activityLevel: ActivityLevel.lightlyActive,
);

const _session = AuthSession(
  uid: 'u1',
  provider: AuthProvider.emailPassword,
  email: 'me@example.com',
  isEmailVerified: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget view, {
    AuthSession? session,
    Profile? profile,
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authSessionProvider.overrideWith((ref) => Stream.value(session)),
        syncStateProvider.overrideWith(
          (ref) => Stream.value(const SyncState(phase: SyncPhase.disabled)),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (profile != null) {
      await container.read(localProfileRepositoryProvider).save(profile);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: view),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('hub lists every category and About', (tester) async {
    await pump(tester, const SettingsView());

    for (final label in const [
      'Appearance',
      'Permissions',
      'Notifications',
      'Preferences',
      'Data & Library',
      'Account',
      'About & Attribution',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('hub shows the signed-in email under Account', (tester) async {
    await pump(tester, const SettingsView(), session: _session);
    expect(find.text('me@example.com'), findsOneWidget);
  });

  testWidgets('Appearance holds theme, colors and units', (tester) async {
    await pump(tester, const AppearanceSettingsView());

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('App Colors'), findsOneWidget);
    expect(find.text('Units'), findsWidgets);
    expect(find.text('Metric'), findsOneWidget);
  });

  testWidgets('Permissions holds media, system settings and health', (
    tester,
  ) async {
    await pump(tester, const PermissionsSettingsView());

    expect(find.text('Media Controls Permission'), findsOneWidget);
    expect(find.text('System app settings'), findsOneWidget);
    expect(find.text('Health Integrations'), findsOneWidget);
  });

  testWidgets('Data & Library holds sync, export and the libraries', (
    tester,
  ) async {
    await pump(tester, const DataLibrarySettingsView());

    for (final label in const [
      'Cloud sync',
      'Export Data (JSON)',
      'Insights',
      'Body Measurements',
      'My Gyms',
      'Micro Workouts',
      'Exercise Library',
      'Custom Foods',
      'Custom Recipes',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  group('Account', () {
    testWidgets('signed out offers sign-in, no account deletion', (
      tester,
    ) async {
      await pump(tester, const AccountSettingsView());

      expect(find.text('Sign in to Supabase'), findsOneWidget);
      expect(find.text('Sign Out'), findsNothing);
      expect(find.text('Delete Account'), findsNothing);
      expect(find.text('Clear All Data'), findsOneWidget);
    });

    testWidgets('signed in offers sign-out and account deletion', (
      tester,
    ) async {
      await pump(tester, const AccountSettingsView(), session: _session);

      expect(find.text('me@example.com'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);
    });
  });

  group('Preferences', () {
    testWidgets('burned-calories switch writes to the stored profile', (
      tester,
    ) async {
      final container = await pump(
        tester,
        const PreferencesSettingsView(),
        profile: _profile,
      );

      final tile = find.ancestor(
        of: find.text('Include Burned Calories'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: tile.first, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      final saved = await container
          .read(localProfileRepositoryProvider)
          .watch()
          .first;
      expect(saved?.countBurnedCalories, isTrue);
      // The other Profile fields survive the write.
      expect(saved?.goal, FitnessGoal.maintenance);
    });

    testWidgets('Honest Hercul needs the 18+ confirmation', (tester) async {
      final container = await pump(
        tester,
        const PreferencesSettingsView(),
        profile: _profile,
      );

      final tile = find.ancestor(
        of: find.text('Honest Hercul (18+)'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: tile.first, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enable Honest Hercul?'), findsOneWidget);
      var saved = await container
          .read(localProfileRepositoryProvider)
          .watch()
          .first;
      expect(saved?.herculTone, 'normal');

      await tester.tap(find.text('Yes, I am 18+'));
      await tester.pumpAndSettle();

      saved = await container
          .read(localProfileRepositoryProvider)
          .watch()
          .first;
      expect(saved?.herculTone, 'honest');
    });
  });
}
