import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/design_system/components/hx_quick_add_button.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

const _tools = [
  HxRailTool(
    icon: Icons.menu_book_rounded,
    label: 'Exercise library',
    path: '/exercises',
    alsoUnder: ['/exercise'],
  ),
  HxRailTool(
    icon: Icons.analytics_rounded,
    label: 'Insights',
    path: '/insights',
  ),
  HxRailTool(icon: Icons.science_outlined, label: 'Labs', path: '/labs'),
];

Future<void> _pumpRail(
  WidgetTester tester, {
  int? index = 0,
  ValueChanged<int>? onTap,
  List<HxRailTool> tools = const [],
  int? currentTool,
  ValueChanged<HxRailTool>? onToolTap,
  VoidCallback? onQuickAdd,
  bool withQuickAdd = true,
  double height = 700,
}) async {
  tester.view.physicalSize = Size(1280, height + 100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.buildTheme(Brightness.dark, AppColorTheme.classicBlue),
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: height,
            child: HxNavRail(
              currentIndex: index,
              onTap: onTap ?? (_) {},
              tools: tools,
              currentTool: currentTool,
              onToolTap: onToolTap,
              onQuickAddTap: withQuickAdd ? (onQuickAdd ?? () {}) : null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSelected(WidgetTester tester, IconData icon, bool selected) {
  final node = tester.getSemantics(find.byIcon(icon));
  final matcher = isSemantics(isSelected: true);
  expect(node, selected ? matcher : isNot(matcher), reason: '$icon');
}

void main() {
  testWidgets('the rail shows the four destinations as icons only', (
    tester,
  ) async {
    await _pumpRail(tester);
    for (final icon in const [
      Icons.grid_view_rounded,
      Icons.restaurant_rounded,
      Icons.fitness_center_rounded,
      Icons.person_rounded,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
    for (final label in const [
      'Dashboard',
      'Nutrition',
      'Workouts',
      'Profile',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(tester.getSize(find.byType(HxNavRail)).width, HxNavRail.width);
  });

  testWidgets('the rail stays narrow however many tools it lists', (
    tester,
  ) async {
    await _pumpRail(tester, tools: _tools);
    expect(tester.getSize(find.byType(HxNavRail)).width, HxNavRail.width);
    for (final tool in _tools) {
      expect(find.byIcon(tool.icon), findsOneWidget);
      expect(find.text(tool.label), findsNothing);
    }
  });

  testWidgets('tapping a destination selects it; the current one is inert', (
    tester,
  ) async {
    final taps = <int>[];
    await _pumpRail(tester, index: 1, onTap: taps.add);
    await tester.tap(find.byIcon(Icons.fitness_center_rounded));
    await tester.tap(find.byIcon(Icons.restaurant_rounded));
    expect(taps, [2]);
  });

  testWidgets('tapping a tool reports it; the open one is inert', (
    tester,
  ) async {
    final opened = <HxRailTool>[];
    await _pumpRail(
      tester,
      index: null,
      currentTool: 1,
      tools: _tools,
      onToolTap: opened.add,
    );
    await tester.tap(find.byIcon(Icons.science_outlined));
    await tester.tap(find.byIcon(Icons.analytics_rounded));
    expect(opened, [_tools[2]]);
  });

  testWidgets('a tool and a tab are never selected together', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpRail(tester, index: null, currentTool: 2, tools: _tools);
    _expectSelected(tester, Icons.science_outlined, true);
    _expectSelected(tester, Icons.analytics_rounded, false);
    for (final icon in const [
      Icons.grid_view_rounded,
      Icons.restaurant_rounded,
      Icons.fitness_center_rounded,
      Icons.person_rounded,
    ]) {
      _expectSelected(tester, icon, false);
    }

    await _pumpRail(tester, index: 2, tools: _tools);
    _expectSelected(tester, Icons.fitness_center_rounded, true);
    _expectSelected(tester, Icons.science_outlined, false);
    handle.dispose();
  });

  testWidgets('the selection bubble follows the selected tool', (tester) async {
    await _pumpRail(tester, index: null, currentTool: 2, tools: _tools);
    final bubble = find.byType(AnimatedPositioned);
    expect(bubble, findsOneWidget);
    expect(
      tester.getCenter(bubble).dy,
      closeTo(tester.getCenter(find.byIcon(Icons.science_outlined)).dy, 1),
    );
  });

  testWidgets('a short window scrolls the destinations, not the quick-add', (
    tester,
  ) async {
    final opened = <HxRailTool>[];
    await _pumpRail(tester, tools: _tools, height: 380, onToolTap: opened.add);
    expect(tester.takeException(), isNull);
    expect(find.byType(HxQuickAddButton).hitTestable(), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.science_outlined));
    expect(opened, [_tools[2]]);
    expect(find.byType(HxQuickAddButton).hitTestable(), findsOneWidget);
  });

  testWidgets('the quick-add button is on the rail', (tester) async {
    var opened = 0;
    await _pumpRail(tester, onQuickAdd: () => opened++);
    await tester.tap(find.byType(HxQuickAddButton));
    expect(opened, 1);
  });

  testWidgets('without a quick-add callback the button is not drawn', (
    tester,
  ) async {
    await _pumpRail(tester, withQuickAdd: false);
    expect(find.byType(HxQuickAddButton), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
  });

  group('HxRailTool.owns', () {
    test('matches its own path and anything beneath it', () {
      expect(_tools[2].owns('/labs'), isTrue);
      expect(_tools[2].owns('/labs/reports'), isTrue);
      expect(_tools[2].owns('/labsx'), isFalse);
      expect(_tools[2].owns('/app'), isFalse);
    });

    test('also claims the extra prefixes it lists', () {
      expect(_tools[0].owns('/exercises'), isTrue);
      expect(_tools[0].owns('/exercise/12'), isTrue);
      expect(_tools[0].owns('/exercise'), isTrue);
      expect(_tools[1].owns('/exercise/12'), isFalse);
    });
  });
}
