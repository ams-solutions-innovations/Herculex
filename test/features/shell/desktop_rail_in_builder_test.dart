import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/features/shell/desktop_app_shell.dart';
import 'package:herculex/features/shell/rail_tools.dart';

/// The real app mounts the rail in `MaterialApp.router(builder:)`, i.e. ABOVE
/// the Navigator and therefore above any Overlay. `MaterialApp(home:)` hides
/// that, so this reproduces the production placement.
void main() {
  testWidgets('rail taps navigate when mounted above the navigator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var tab = 0;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/labs', builder: (_, _) => const Text('labs')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities.web(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => DesktopAppShell(
            location: '/',
            currentIndex: tab,
            onSelectTab: (i) => tab = i,
            tools: railTools,
            currentTool: null,
            onSelectTool: (t) => router.go('/labs'),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Hover first, like a mouse does before clicking.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.science_outlined)));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull, reason: 'hover over rail item');

    await tester.tap(find.byIcon(Icons.science_outlined));
    await tester.pumpAndSettle();
    expect(find.text('labs'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restaurant_rounded).first);
    await tester.pumpAndSettle();
    expect(tab, 1);
    expect(find.byType(HxNavRail), findsOneWidget);
  });
}
