import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/dashboard/domain/dashboard_config.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_view.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_customize_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dashboard Widget Stacking Compatibility Classification', () {
    test('Card-tier widgets all share DashboardWidgetKind.card', () {
      final cardTypes = [
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.herculInsights,
        DashboardWidgetType.recoverySummary,
        DashboardWidgetType.supplements,
        DashboardWidgetType.quickScan,
        DashboardWidgetType.miniWorkouts,
        DashboardWidgetType.latestPrs,
        DashboardWidgetType.calorieTrends,
        DashboardWidgetType.remainingCalories,
        DashboardWidgetType.todaysPlan,
        DashboardWidgetType.cycle,
      ];

      for (final type in cardTypes) {
        expect(
          type.kind,
          DashboardWidgetKind.card,
          reason: '${type.label} should have kind card',
        );
      }
    });

    test('Pill-tier widgets all share DashboardWidgetKind.pill', () {
      final pillTypes = [
        DashboardWidgetType.workoutStreak,
        DashboardWidgetType.cnsLoad,
        DashboardWidgetType.nutritionStreak,
        DashboardWidgetType.weeklyVolume,
      ];

      for (final type in pillTypes) {
        expect(
          type.kind,
          DashboardWidgetKind.pill,
          reason: '${type.label} should have kind pill',
        );
      }
    });

    test('Large-tier widgets remain DashboardWidgetKind.large', () {
      final largeTypes = [
        DashboardWidgetType.fastingTimer,
        DashboardWidgetType.macros,
        DashboardWidgetType.workoutCalendar,
      ];

      for (final type in largeTypes) {
        expect(
          type.kind,
          DashboardWidgetKind.large,
          reason: '${type.label} should have kind large',
        );
      }
    });

    test('Stacking Card-tier widgets creates multi-item stack config', () {
      var config = DashboardConfig.defaults;
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.herculInsights,
      );
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.recoverySummary,
      );
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.supplements,
      );
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.quickScan,
      );
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.miniWorkouts,
      );
      config = config.stackWidgets(
        DashboardWidgetType.bodyweightTrends,
        DashboardWidgetType.latestPrs,
      );

      final stackSlot = config.widgets.firstWhere(
        (w) => w.types.contains(DashboardWidgetType.bodyweightTrends),
      );

      expect(stackSlot.isStack, isTrue);
      expect(stackSlot.types, contains(DashboardWidgetType.bodyweightTrends));
      expect(stackSlot.types, contains(DashboardWidgetType.herculInsights));
      expect(stackSlot.types, contains(DashboardWidgetType.recoverySummary));
      expect(stackSlot.types, contains(DashboardWidgetType.supplements));
      expect(stackSlot.types, contains(DashboardWidgetType.quickScan));
      expect(stackSlot.types, contains(DashboardWidgetType.miniWorkouts));
      expect(stackSlot.types, contains(DashboardWidgetType.latestPrs));

      final encoded = config.encode();
      final decoded = DashboardConfig.decode(encoded);
      final decodedSlot = decoded.widgets.firstWhere(
        (w) => w.types.contains(DashboardWidgetType.bodyweightTrends),
      );
      expect(decodedSlot.types, equals(stackSlot.types));
    });

    test('Stacking Pill-tier widgets creates multi-item streak/load stack', () {
      var config = DashboardConfig.defaults;
      config = config.stackWidgets(
        DashboardWidgetType.workoutStreak,
        DashboardWidgetType.cnsLoad,
      );
      config = config.stackWidgets(
        DashboardWidgetType.workoutStreak,
        DashboardWidgetType.nutritionStreak,
      );
      config = config.stackWidgets(
        DashboardWidgetType.workoutStreak,
        DashboardWidgetType.weeklyVolume,
      );

      final stackSlot = config.widgets.firstWhere(
        (w) => w.types.contains(DashboardWidgetType.workoutStreak),
      );

      expect(stackSlot.isStack, isTrue);
      expect(stackSlot.types, contains(DashboardWidgetType.workoutStreak));
      expect(stackSlot.types, contains(DashboardWidgetType.cnsLoad));
      expect(stackSlot.types, contains(DashboardWidgetType.nutritionStreak));
      expect(stackSlot.types, contains(DashboardWidgetType.weeklyVolume));

      final unstacked = config.unstackWidget(DashboardWidgetType.cnsLoad);
      final remainingSlot = unstacked.widgets.firstWhere(
        (w) => w.types.contains(DashboardWidgetType.workoutStreak),
      );
      expect(remainingSlot.types.contains(DashboardWidgetType.cnsLoad), isFalse);
    });
  });

  testWidgets('DashboardCustomizeSheet renders in bottom sheet without Material error', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const DashboardCustomizeSheet(),
                  );
                },
                child: const Text('Customize'),
              ),
            ),
          ),
        ),
      ),
    );

    // Tap Customize to open the bottom sheet
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();

    // Verify header and shape cards exist
    expect(find.text('Customize Dashboard'), findsOneWidget);
    expect(find.text('WIDGET SHAPE'), findsOneWidget);
    expect(find.text('Squircle'), findsWidgets);
    expect(find.text('Pill'), findsWidgets);
    expect(find.text('Compact'), findsWidgets);

    // Verify widgets in the reorderable list are present
    expect(find.text('Fasting Timer'), findsOneWidget);
    expect(find.text('Supplements Tracker'), findsOneWidget);
    expect(find.text('Calories Remaining'), findsOneWidget);
    expect(find.text('STACK (2)'), findsOneWidget);

    // Tap a different shape chip
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();

    // Tap unstack on one of the stacked items
    final unstackButtons = find.byTooltip('Unstack widget');
    expect(unstackButtons, findsWidgets);
    await tester.tap(unstackButtons.first);
    await tester.pumpAndSettle();

    // Verify no Flutter error widgets or Material exceptions were thrown
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard stacked widgets support horizontal swiping through multi-card stack', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return StackedDashboardWidget(
                  types: const [
                    DashboardWidgetType.bodyweightTrends,
                    DashboardWidgetType.herculInsights,
                    DashboardWidgetType.recoverySummary,
                    DashboardWidgetType.supplements,
                    DashboardWidgetType.quickScan,
                    DashboardWidgetType.miniWorkouts,
                    DashboardWidgetType.latestPrs,
                  ],
                  theme: Theme.of(context),
                  renderWidget: (type) => Center(
                    child: Text('WIDGET_${type.name}'),
                  ),
                  onLongPress: () {},
                );
              },
            ),
          ),
        ),
      ),
    );

    // Initial page shows bodyweight trends widget
    expect(find.text('WIDGET_bodyweightTrends'), findsOneWidget);
    expect(find.text('WIDGET_herculInsights'), findsNothing);

    // Swipe left to go to next page
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();

    // Now hercul insights widget is visible
    expect(find.text('WIDGET_herculInsights'), findsOneWidget);
    expect(find.text('WIDGET_bodyweightTrends'), findsNothing);

    // Swipe left again -> recovery
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('WIDGET_recoverySummary'), findsOneWidget);

    // Swipe left again -> supplements
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('WIDGET_supplements'), findsOneWidget);

    // Swipe right to go back
    await tester.fling(find.byType(PageView), const Offset(600, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('WIDGET_recoverySummary'), findsOneWidget);
  });

  testWidgets('Dashboard stacked widgets support horizontal swiping through pill stack', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return StackedDashboardWidget(
                  types: const [
                    DashboardWidgetType.workoutStreak,
                    DashboardWidgetType.cnsLoad,
                    DashboardWidgetType.nutritionStreak,
                  ],
                  theme: Theme.of(context),
                  renderWidget: (type) => Center(
                    child: Text('PILL_${type.name}'),
                  ),
                  onLongPress: () {},
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('PILL_workoutStreak'), findsOneWidget);
    expect(find.text('PILL_cnsLoad'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('PILL_cnsLoad'), findsOneWidget);
    expect(find.text('PILL_workoutStreak'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('PILL_nutritionStreak'), findsOneWidget);
  });
}
