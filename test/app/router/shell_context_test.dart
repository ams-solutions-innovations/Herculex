import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/shell_context.dart';

void main() {
  late GoRouter router;

  /// Returns the context of a widget above the `MaterialApp`, which is where
  /// `_HerculexAppState` lives.
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const Text('splash')),
        GoRoute(path: '/app', builder: (_, _) => const Text('shell')),
      ],
    );
    addTearDown(router.dispose);
    late BuildContext aboveApp;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          aboveApp = context;
          return MaterialApp.router(routerConfig: router);
        },
      ),
    );
    return aboveApp;
  }

  testWidgets('a context above MaterialApp cannot open a sheet', (
    tester,
  ) async {
    final aboveApp = await pumpApp(tester);

    expect(
      () => showModalBottomSheet<void>(
        context: aboveApp,
        builder: (_) => const SizedBox(),
      ),
      throwsFlutterError,
    );
  });

  testWidgets('waits for the shell, then returns a context that can', (
    tester,
  ) async {
    await pumpApp(tester);
    BuildContext? shell;
    final pending = awaitShellContext(router).then((c) => shell = c);

    // Still on the splash screen: nothing to hand out yet.
    await tester.pump(const Duration(milliseconds: 200));
    expect(shell, isNull);

    router.go('/app');
    for (var i = 0; i < 5 && shell == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await pending;

    expect(shell, isNotNull);
    showModalBottomSheet<void>(
      context: shell!,
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
  });

  testWidgets('gives up when the shell never shows', (tester) async {
    await pumpApp(tester);

    final pending = awaitShellContext(
      router,
      timeout: const Duration(milliseconds: 200),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(await pending, isNull);
  });
}
