import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/features/shell/router_location_builder.dart';

GoRouter _router() => GoRouter(
  routes: [
    for (final path in ['/', '/insights', '/exercise/:id'])
      GoRoute(path: path, builder: (_, _) => Text('screen $path')),
  ],
);

Future<List<String>> _pump(WidgetTester tester, GoRouter router) async {
  final seen = <String>[];
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => RouterLocationBuilder(
        router: router,
        builder: (context, location) {
          seen.add(location);
          return child!;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return seen;
}

void main() {
  testWidgets('reports the screen on top of the stack as it changes', (
    tester,
  ) async {
    final router = _router();
    final seen = await _pump(tester, router);
    expect(seen.last, '/');

    router.push<void>('/insights');
    await tester.pumpAndSettle();
    expect(seen.last, '/insights');

    // Filled-in paths, not the route pattern.
    router.push<void>('/exercise/12');
    await tester.pumpAndSettle();
    expect(seen.last, '/exercise/12');

    router.pop();
    await tester.pumpAndSettle();
    expect(seen.last, '/insights');

    router.go('/');
    await tester.pumpAndSettle();
    expect(seen.last, '/');
  });

  testWidgets('does not rebuild when the location is unchanged', (
    tester,
  ) async {
    final router = _router();
    final seen = await _pump(tester, router);
    final before = seen.length;

    router.go('/');
    await tester.pumpAndSettle();
    expect(seen.length, before);
  });

  testWidgets('stops listening when removed', (tester) async {
    final router = _router();
    await _pump(tester, router);
    await tester.pumpWidget(const SizedBox());

    router.push<void>('/insights');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
