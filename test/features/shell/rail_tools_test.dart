import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/features/shell/rail_tools.dart';

HxRailToolsFixture _fixture() => HxRailToolsFixture();

/// A router with a stub screen for each rail tool and the home shell.
class HxRailToolsFixture {
  HxRailToolsFixture()
    : router = GoRouter(
        initialLocation: AppRoutes.app,
        routes: [
          for (final path in [AppRoutes.app, AppRoutes.recovery])
            GoRoute(path: path, builder: (_, _) => Text('screen $path')),
          for (final tool in railTools)
            GoRoute(path: tool.path, builder: (_, _) => Text(tool.path)),
        ],
      );

  final GoRouter router;

  String get location =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;
}

void main() {
  group('railTools', () {
    test('every tool opens a registered route', () {
      // A rail icon that lands on the error screen is worse than no icon.
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) => Stream.value(null))],
      );
      addTearDown(container.dispose);
      final registered = [
        for (final route in container.read(routerProvider).configuration.routes)
          if (route is GoRoute) route.path,
      ];
      for (final tool in railTools) {
        expect(registered, contains(tool.path), reason: tool.label);
      }
    });

    test('none of them is phone-only on the web', () {
      for (final tool in railTools) {
        expect(
          nativeOnlyRoutes,
          isNot(contains(tool.path)),
          reason: '${tool.label} would redirect to "not on web"',
        );
      }
    });

    test('labels and paths are unique', () {
      expect({for (final t in railTools) t.label}.length, railTools.length);
      expect({for (final t in railTools) t.path}.length, railTools.length);
    });

    test('Labs is among them', () {
      expect(railTools.map((t) => t.path), contains(AppRoutes.labs));
    });
  });

  group('railToolIndexFor', () {
    int indexOf(String path) => railTools.indexWhere((t) => t.path == path);

    test('picks the tool whose screen is open', () {
      expect(railToolIndexFor(AppRoutes.insights), indexOf(AppRoutes.insights));
      expect(railToolIndexFor(AppRoutes.labs), indexOf(AppRoutes.labs));
    });

    test('keeps a tool selected on its detail pages', () {
      expect(
        railToolIndexFor(AppPaths.exercise(7)),
        indexOf(AppRoutes.exercises),
      );
      expect(
        railToolIndexFor(AppPaths.measurementDetail('bodyweight')),
        indexOf(AppRoutes.measurements),
      );
      expect(
        railToolIndexFor(AppRoutes.fastingHistory),
        indexOf(AppRoutes.fasting),
      );
    });

    test('is null on the home shell and on screens of no tool', () {
      expect(railToolIndexFor(AppRoutes.app), isNull);
      expect(railToolIndexFor(AppRoutes.settings), isNull);
      expect(railToolIndexFor(''), isNull);
    });
  });

  group('openRailTool', () {
    testWidgets('replaces the screen instead of stacking tools', (
      tester,
    ) async {
      final f = _fixture();
      await tester.pumpWidget(MaterialApp.router(routerConfig: f.router));
      await tester.pumpAndSettle();

      final insights = railTools.firstWhere(
        (t) => t.path == AppRoutes.insights,
      );
      final labs = railTools.firstWhere((t) => t.path == AppRoutes.labs);

      openRailTool(f.router, insights);
      await tester.pumpAndSettle();
      expect(f.location, AppRoutes.insights);

      openRailTool(f.router, labs);
      await tester.pumpAndSettle();
      expect(f.location, AppRoutes.labs);
      expect(find.text(AppRoutes.insights), findsNothing);

      // Selecting a tab returns to the home shell without stacking.
      f.router.go(AppRoutes.app);
      await tester.pumpAndSettle();
      expect(f.location, AppRoutes.app);
    });

    testWidgets('works from a screen that belongs to no tool', (tester) async {
      final f = _fixture();
      await tester.pumpWidget(MaterialApp.router(routerConfig: f.router));
      await tester.pumpAndSettle();

      f.router.push<void>(AppRoutes.recovery);
      await tester.pumpAndSettle();
      expect(f.location, AppRoutes.recovery);

      openRailTool(f.router, railTools.first);
      await tester.pumpAndSettle();
      expect(f.location, railTools.first.path);

      f.router.go(AppRoutes.app);
      await tester.pumpAndSettle();
      expect(f.location, AppRoutes.app);
    });
  });
}
