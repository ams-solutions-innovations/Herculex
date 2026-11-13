import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/design_system/components/hx_quick_add_button.dart';
import 'package:herculex/features/shell/desktop_app_shell.dart';
import 'package:herculex/features/shell/quick_add_menu.dart';
import 'package:herculex/features/shell/rail_tools.dart';

void main() {
  testWidgets(
    'DesktopAppShell displays persistent rail and "+" button on wide web',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformCapabilitiesProvider.overrideWithValue(
              const PlatformCapabilities.web(),
            ),
          ],
          child: MaterialApp(
            home: DesktopAppShell(
              location: AppRoutes.exercises,
              currentIndex: 0,
              onSelectTab: (_) {},
              tools: railTools,
              currentTool: 0,
              onSelectTool: (_) {},
              child: const Text('Exercise Library Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Content is displayed
      expect(find.text('Exercise Library Content'), findsOneWidget);

      // Persistent rail is present
      expect(find.byType(HxNavRail), findsOneWidget);

      // Quick add "+" button is present even on Exercise Library
      expect(find.byType(HxQuickAddButton), findsOneWidget);

      // Tapping the "+" button opens QuickAddMenu
      await tester.tap(find.byType(HxQuickAddButton));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAddMenu), findsOneWidget);
    },
  );

  testWidgets('DesktopAppShell does not display rail on auth routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities.web(),
          ),
        ],
        child: MaterialApp(
          home: DesktopAppShell(
            location: AppRoutes.signIn,
            currentIndex: 0,
            onSelectTab: (_) {},
            tools: railTools,
            currentTool: null,
            onSelectTool: (_) {},
            child: const Text('Sign In Content'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign In Content'), findsOneWidget);
    expect(find.byType(HxNavRail), findsNothing);
  });
}
