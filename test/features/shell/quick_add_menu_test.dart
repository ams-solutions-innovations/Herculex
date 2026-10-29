import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/shell/quick_add_menu.dart';

Future<void> _pump(WidgetTester tester, PlatformCapabilities caps) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(caps),
        activeFastingSessionProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: AppTheme.buildTheme(Brightness.dark, AppColorTheme.classicBlue),
        home: Scaffold(
          body: Stack(
            children: [QuickAddMenu(onClose: () {}, leftAnchor: 108)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on the phone the menu starts a quick workout', (tester) async {
    await _pump(
      tester,
      const PlatformCapabilities(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
    );
    expect(find.text('Quick workout'), findsOneWidget);
    expect(find.text('Gym Buddy'), findsOneWidget);
  });

  testWidgets('on the web there is no way to start a workout from the menu', (
    tester,
  ) async {
    await _pump(tester, const PlatformCapabilities.web());
    expect(find.text('Quick workout'), findsNothing);
    expect(find.text('Gym Buddy'), findsNothing);
    // Logging stays.
    expect(find.text('Log food'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Start Quick Fast'), findsOneWidget);
  });
}
