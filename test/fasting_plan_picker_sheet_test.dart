import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_plan_picker_sheet.dart';
import 'package:herculex/features/fasting/presentation/widgets/start_fast_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FastingPlanPickerSheet', () {
    testWidgets('renders intermittent and prolonged tabs in English', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FastingPlanPickerSheet(
              selectedPlan: FastingPlan.h16,
              customTargetHours: 16,
              onPlanSelected: (_) {},
              onCustomHoursChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify title, subtitle, and tab headers in English
      expect(find.text('Select Fasting Plan'), findsOneWidget);
      expect(
        find.text('Choose an intermittent or prolonged protocol'),
        findsOneWidget,
      );
      expect(find.text('Intermittent'), findsOneWidget);
      expect(find.text('Prolonged'), findsOneWidget);

      // Intermittent plans should be visible initially
      expect(find.text('16:8'), findsOneWidget);
      expect(find.text('Quick Fast'), findsOneWidget);
      expect(find.text('12:12'), findsOneWidget);
      expect(find.text('NORMAL & INTERMITTENT PROTOCOLS'), findsOneWidget);
    });

    testWidgets('switches to prolonged tab and shows multi-day protocols', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FastingPlanPickerSheet(
              selectedPlan: FastingPlan.h16,
              customTargetHours: 16,
              onPlanSelected: (_) {},
              onCustomHoursChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the Prolonged tab
      await tester.tap(find.text('Prolonged'));
      await tester.pumpAndSettle();

      // Prolonged protocols should now be visible
      expect(find.text('EXTENDED MULTI-DAY PROTOCOLS'), findsOneWidget);
      expect(find.text('24h'), findsOneWidget);
      expect(find.text('48h'), findsOneWidget);
      expect(find.text('72h'), findsOneWidget);
    });

    testWidgets('calls onPlanSelected when an intermittent plan is tapped', (
      tester,
    ) async {
      FastingPlan? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FastingPlanPickerSheet(
              selectedPlan: FastingPlan.h16,
              customTargetHours: 16,
              onPlanSelected: (p) => selected = p,
              onCustomHoursChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.text('18:6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('18:6'));
      await tester.pump();

      expect(selected, FastingPlan.h18);
    });
  });

  group('StartFastPanel', () {
    testWidgets('renders selected plan card, quick buttons, and start time in English', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StartFastPanel(
              selectedPlan: FastingPlan.h16,
              customTargetHours: 16,
              customStartTime: null,
              onPlanSelected: (_) {},
              onCustomHoursChanged: (_) {},
              onCustomStartTimeChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('READY TO START FASTING?'), findsOneWidget);
      expect(find.text('INTERMITTENT'), findsWidgets);
      expect(find.text('16:8'), findsOneWidget);
      expect(find.text('Change Plan'), findsOneWidget);
      expect(find.text('Intermittent'), findsOneWidget);
      expect(find.text('Prolonged'), findsOneWidget);
      expect(find.text('Start time:'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
    });
  });
}
