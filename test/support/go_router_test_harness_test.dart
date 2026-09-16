import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'go_router_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'push against a parameterised stub route renders the pushed path param',
    (tester) async {
      final harness = GoRouterTestHarness(
        home: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => GoRouter.of(context).push('/target/42'),
              child: const Text('Go'),
            ),
          ),
        ),
        stubRoutes: {
          '/target/:id': (context, state) => StubRouteScreen(
            label: 'Target',
            value: state.pathParameters['id'],
          ),
        },
      );

      await tester.pumpWidget(harness.app);

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Target:42'), findsOneWidget);
    },
  );

  testWidgets('renders the home builder at the initial location with no '
      'stub routes pushed', (tester) async {
    final harness = GoRouterTestHarness(
      home: (context) => const Scaffold(body: Center(child: Text('Home'))),
    );

    await tester.pumpWidget(harness.app);

    expect(find.text('Home'), findsOneWidget);
  });
}
