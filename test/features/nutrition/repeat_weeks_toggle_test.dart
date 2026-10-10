import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/presentation/widgets/repeat_weeks_toggle.dart';
import 'package:herculex/features/nutrition/presentation/widgets/scan_variant_form.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('RepeatWeeksToggle', () {
    testWidgets('hides the week choices while off', (tester) async {
      await tester.pumpWidget(
        host(
          RepeatWeeksToggle(
            enabled: false,
            weeks: 4,
            onEnabledChanged: (_) {},
            onWeeksChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Only this week'), findsOneWidget);
      expect(find.text('4 weeks'), findsNothing);
    });

    testWidgets('shows the week choices and reports a pick', (tester) async {
      int? picked;
      await tester.pumpWidget(
        host(
          RepeatWeeksToggle(
            enabled: true,
            weeks: 4,
            onEnabledChanged: (_) {},
            onWeeksChanged: (value) => picked = value,
          ),
        ),
      );

      expect(find.text('Same days, every week for 4 weeks'), findsOneWidget);
      for (final label in ['2 weeks', '4 weeks', '8 weeks', '12 weeks']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('8 weeks'));
      expect(picked, 8);
    });

    testWidgets('reports the switch being turned on', (tester) async {
      bool? enabled;
      await tester.pumpWidget(
        host(
          RepeatWeeksToggle(
            enabled: false,
            weeks: 4,
            onEnabledChanged: (value) => enabled = value,
            onWeeksChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      expect(enabled, isTrue);
    });
  });

  group('ScanVariantChips', () {
    testWidgets('lists every table and reports the chosen one', (tester) async {
      int? chosen;
      await tester.pumpWidget(
        host(
          ScanVariantChips(
            labels: const ['Not drained', 'Drained'],
            selected: 0,
            onSelected: (i) => chosen = i,
          ),
        ),
      );

      expect(find.textContaining('2 nutrition tables'), findsOneWidget);
      expect(find.text('Not drained'), findsOneWidget);

      await tester.tap(find.text('Drained'));
      expect(chosen, 1);
    });
  });
}
