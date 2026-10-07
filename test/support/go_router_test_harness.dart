import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';

/// A minimal, reusable `GoRouter` harness for widget tests.
///
/// No test in this repository pumps a widget under `MaterialApp.router` or
/// exercises `context.push` today — `DayDetailSheet` is only ever tested
/// with a bare `MaterialApp(home: Scaffold(...))`
/// (`test/widgets/day_detail_sheet_test.dart`). This harness closes that gap
/// (see phase 20 RESEARCH.md Pitfall 2): it builds a real `GoRouter` from a
/// caller-supplied `home` builder plus a map of stub destination routes, so
/// tests can pump a screen, tap something that calls
/// `context.push('/target/:id')`, and assert on the resulting stub screen's
/// rendered path parameter — with zero dependency on any production route
/// constant existing yet.
///
/// Usage:
/// ```dart
/// final harness = GoRouterTestHarness(
///   home: (context) => ElevatedButton(
///     onPressed: () => GoRouter.of(context).push('/target/42'),
///     child: const Text('Go'),
///   ),
///   stubRoutes: {
///     '/target/:id': (context, state) =>
///         StubRouteScreen(label: 'Target', value: state.pathParameters['id']),
///   },
/// );
/// await tester.pumpWidget(harness.app);
/// await tester.tap(find.text('Go'));
/// await tester.pumpAndSettle();
/// expect(find.text('Target:42'), findsOneWidget);
/// ```
class GoRouterTestHarness {
  GoRouterTestHarness({
    required WidgetBuilder home,
    Map<String, Widget Function(BuildContext, GoRouterState)> stubRoutes =
        const {},
    String initialLocation = '/',
  }) : router = GoRouter(
         initialLocation: initialLocation,
         routes: [
           GoRoute(path: '/', builder: (context, _) => home(context)),
           for (final entry in stubRoutes.entries)
             GoRoute(path: entry.key, builder: entry.value),
         ],
       );

  /// The `GoRouter` built from the harness's `home` builder and `stubRoutes`.
  final GoRouter router;

  /// A `MaterialApp.router` ready to hand straight to `tester.pumpWidget`.
  Widget get app => MaterialApp.router(
    // Same host the real app wraps every route in, so notices are visible.
    builder: (context, child) => InAppNotificationHost(child: child!),
    routerConfig: router,
  );
}

/// A minimal stub destination screen for asserting on pushed routes.
///
/// Renders `label` alone, or `label:value` when `value` is supplied (e.g.
/// the id/param the route was pushed with) — giving tests a single
/// `find.text('Label:value')` target to assert against after a push.
class StubRouteScreen extends StatelessWidget {
  const StubRouteScreen({super.key, required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(value == null ? label : '$label:$value')),
    );
  }
}
