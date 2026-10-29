import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/hx_layout_scope.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required double width,
  HxShellNavigationScope Function(Widget child)? scope,
  HxNavPlacement? placement,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget page = const HxScreenShell(
    title: 'Dream Physique AI',
    children: [Text('page body')],
  );
  if (placement != null) {
    page = HxLayoutScope(placement: placement, child: page);
  }
  if (scope != null) page = scope(page);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.buildTheme(Brightness.dark, AppColorTheme.classicBlue),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

const _labs = HxRailTool(
  icon: Icons.science_outlined,
  label: 'Labs',
  path: '/labs',
);

HxShellNavigationScope _scope(
  Widget child, {
  bool enabled = true,
  ValueChanged<int>? onSelect,
  List<HxRailTool> tools = const [],
  int? currentTool,
  ValueChanged<HxRailTool>? onSelectTool,
}) => HxShellNavigationScope(
  enabled: enabled,
  currentIndex: 2,
  onSelectTab: onSelect ?? (_) {},
  tools: tools,
  currentTool: currentTool,
  onSelectTool: onSelectTool,
  child: child,
);

void main() {
  testWidgets('a wide window shows the rail beside a pushed screen', (
    tester,
  ) async {
    await _pumpShell(tester, width: 1280, scope: _scope);

    expect(find.byType(HxNavRail), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_rounded), findsWidgets);
    // The rail is icon-only at every width.
    expect(find.text('Workouts'), findsNothing);
    expect(tester.getSize(find.byType(HxNavRail)).width, HxNavRail.width);

    final rail = tester.getRect(find.byType(HxNavRail));
    final body = tester.getRect(find.text('page body'));
    expect(body.left, greaterThan(rail.right));
  });

  testWidgets('quick-add is not offered on pushed screens', (tester) async {
    await _pumpShell(tester, width: 1280, scope: _scope);
    expect(
      tester.widget<HxNavRail>(find.byType(HxNavRail)).onQuickAddTap,
      isNull,
    );
  });

  testWidgets('a narrow window keeps the phone layout without a rail', (
    tester,
  ) async {
    await _pumpShell(tester, width: 600, scope: _scope);
    expect(find.byType(HxNavRail), findsNothing);
  });

  testWidgets('the rail switches on at the breakpoint', (tester) async {
    await _pumpShell(tester, width: HxBreakpoints.rail - 1, scope: _scope);
    expect(find.byType(HxNavRail), findsNothing);

    await _pumpShell(tester, width: HxBreakpoints.rail, scope: _scope);
    expect(find.byType(HxNavRail), findsOneWidget);
  });

  testWidgets('without the scope (phone, tests) no rail is drawn', (
    tester,
  ) async {
    await _pumpShell(tester, width: 1280);
    expect(find.byType(HxNavRail), findsNothing);
  });

  testWidgets('a disabled scope (native desktop) draws no rail', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      width: 1280,
      scope: (child) => _scope(child, enabled: false),
    );
    expect(find.byType(HxNavRail), findsNothing);
  });

  testWidgets('inside the main shell the rail is not drawn twice', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      width: 1280,
      scope: _scope,
      placement: HxNavPlacement.rail,
    );
    expect(find.byType(HxNavRail), findsNothing);
  });

  testWidgets('tapping a rail destination reports its tab', (tester) async {
    final selected = <int>[];
    await _pumpShell(
      tester,
      width: 1280,
      scope: (child) => _scope(child, onSelect: selected.add),
    );

    await tester.tap(find.byIcon(Icons.restaurant_rounded));
    expect(selected, [1]);
  });

  testWidgets('the rail lists the tools and reports the one tapped', (
    tester,
  ) async {
    final opened = <HxRailTool>[];
    await _pumpShell(
      tester,
      width: 1280,
      scope: (child) =>
          _scope(child, tools: const [_labs], onSelectTool: opened.add),
    );

    await tester.tap(find.byIcon(Icons.science_outlined));
    expect(opened, [_labs]);
  });

  testWidgets('an open tool takes the highlight from the last tab', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      width: 1280,
      scope: (child) => _scope(child, tools: const [_labs], currentTool: 0),
    );
    final rail = tester.widget<HxNavRail>(find.byType(HxNavRail));
    expect(rail.currentTool, 0);
    expect(rail.currentIndex, isNull);

    await _pumpShell(
      tester,
      width: 1280,
      scope: (child) => _scope(child, tools: const [_labs]),
    );
    final home = tester.widget<HxNavRail>(find.byType(HxNavRail));
    expect(home.currentTool, isNull);
    expect(home.currentIndex, 2);
  });
}
