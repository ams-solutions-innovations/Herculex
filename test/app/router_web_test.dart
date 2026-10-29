import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:herculex/features/auth/presentation/sign_in_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/shell/not_on_web_view.dart';
import 'package:herculex/features/shell/restoring_view.dart';

const _profile = Profile(
  goal: FitnessGoal.maintenance,
  activityLevel: ActivityLevel.active,
  weightKg: 80,
  heightCm: 180,
  ageYears: 28,
);

const _session = AuthSession(
  uid: 'user-1',
  email: 'athlete@herculex.app',
  displayName: 'Athlete',
  provider: AuthProvider.emailPassword,
  idToken: 'token',
  isEmailVerified: true,
);

/// The production router, opened at [location] in a web build with the given
/// account state.
Future<GoRouter> _pumpWebAt(
  WidgetTester tester,
  String location, {
  AuthSession? session = _session,
  bool restored = true,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      platformCapabilitiesProvider.overrideWithValue(
        const PlatformCapabilities.web(),
      ),
      // Tests have no Supabase credentials; gate as a configured web build.
      accountRequiredProvider.overrideWithValue(true),
      profileProvider.overrideWith((ref) => Stream.value(_profile)),
      authSessionProvider.overrideWith((ref) => Stream.value(session)),
      initialSyncReadyProvider.overrideWith((ref) => Stream.value(restored)),
    ],
  );
  addTearDown(container.dispose);
  // Let the streams emit so the redirect sees settled values.
  await container.read(profileProvider.future);
  await container.read(authSessionProvider.future);
  await container.read(initialSyncReadyProvider.future);

  final router = container.read(routerProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.buildTheme(Brightness.dark, AppColorTheme.classicBlue),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return router;
}

Uri _location(GoRouter router) => router.routeInformationProvider.value.uri;

void main() {
  group('web routing', () {
    test('every native-only route and web route is registered', () {
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) => Stream.value(null))],
      );
      addTearDown(container.dispose);
      final paths = [
        for (final route in container.read(routerProvider).configuration.routes)
          if (route is GoRoute) route.path,
      ];
      expect(paths, containsAll(nativeOnlyRoutes));
      expect(
        paths,
        containsAll([
          AppRoutes.notOnWeb,
          AppRoutes.signIn,
          AppRoutes.resetPassword,
          AppRoutes.restoring,
        ]),
      );
    });

    test('AppPaths.notOnWeb carries the original path', () {
      expect(
        AppPaths.notOnWeb(AppRoutes.health),
        '${AppRoutes.notOnWeb}?from=%2Fhealth',
      );
    });

    for (final location in [
      AppRoutes.health,
      AppRoutes.notifications,
      AppRoutes.gymBuddy,
    ]) {
      testWidgets('$location shows NotOnWebView on the web', (tester) async {
        final router = await _pumpWebAt(tester, location);
        expect(find.byType(NotOnWebView), findsOneWidget);
        expect(find.text('Available in the mobile app'), findsOneWidget);
        expect(_location(router).queryParameters['from'], location);
      });
    }

    testWidgets('without a session the web lands on sign-in', (tester) async {
      final router = await _pumpWebAt(tester, AppRoutes.app, session: null);
      expect(find.byType(SignInView), findsOneWidget);
      expect(_location(router).path, AppRoutes.signIn);
      expect(_location(router).queryParameters, isEmpty);
    });

    testWidgets('a deep link survives the trip through sign-in', (
      tester,
    ) async {
      final router = await _pumpWebAt(tester, AppRoutes.cycle, session: null);
      expect(_location(router).path, AppRoutes.signIn);
      expect(_location(router).queryParameters['from'], AppRoutes.cycle);
    });

    testWidgets('signed in but not restored waits on /restoring', (
      tester,
    ) async {
      final router = await _pumpWebAt(tester, AppRoutes.app, restored: false);
      expect(find.byType(RestoringView), findsOneWidget);
      expect(_location(router).path, AppRoutes.restoring);
    });

    testWidgets('a signed-in user is sent on from sign-in to its from link', (
      tester,
    ) async {
      final router = await _pumpWebAt(
        tester,
        '${AppRoutes.signIn}?from=${Uri.encodeComponent(AppRoutes.notOnWeb)}',
      );
      expect(_location(router).path, AppRoutes.notOnWeb);
    });

    test('only in-app paths are honoured as from targets', () {
      expect(safeRedirectTarget('/insights'), '/insights');
      expect(safeRedirectTarget('//evil.example'), isNull);
      expect(safeRedirectTarget('https://evil.example'), isNull);
      expect(safeRedirectTarget('insights'), isNull);
      expect(safeRedirectTarget(null), isNull);
    });
  });
}
