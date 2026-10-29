import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/hx_masonry.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/workouts/presentation/views/set_types_guide_view.dart';
import 'package:herculex/features/workouts/presentation/widgets/set_type_menu.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  String? highlight,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.buildTheme(Brightness.dark, AppColorTheme.classicBlue),
      home: SetTypesGuideView(highlight: highlight),
    ),
  );
  await tester.pumpAndSettle();
}

/// How many distinct left edges the built cards have.
int _cardColumns(WidgetTester tester) => {
  for (final card in find.byType(SetTypeGuideCard).evaluate())
    tester.getTopLeft(find.byWidget(card.widget)).dx,
}.length;

void main() {
  testWidgets('explains drop sets and myo reps on a screen of its own', (
    tester,
  ) async {
    await _pump(tester, width: 1100);

    expect(find.text('Training Techniques'), findsOneWidget);
    expect(find.text('Drop Set'), findsOneWidget);
    expect(find.text('Myo Reps'), findsOneWidget);
    expect(
      find.textContaining('immediately reduce weight by 10–30%'),
      findsOneWidget,
    );
  });

  testWidgets('searching narrows the list to the matching technique', (
    tester,
  ) async {
    await _pump(tester, width: 1100);

    await tester.enterText(find.byType(TextField), 'myo');
    await tester.pumpAndSettle();

    expect(find.byType(SetTypeGuideCard), findsOneWidget);
    expect(find.text('Myo Reps'), findsOneWidget);
    expect(find.text('Drop Set'), findsNothing);
  });

  testWidgets('a category chip filters to that category', (tester) async {
    await _pump(tester, width: 1100);

    await tester.tap(find.widgetWithText(FilterChip, 'Timed & Functional'));
    await tester.pumpAndSettle();

    expect(find.text('AMRAP'), findsOneWidget);
    expect(find.text('Drop Set'), findsNothing);
  });

  testWidgets('?type= puts that technique first and outlines it', (
    tester,
  ) async {
    await _pump(tester, width: 1100, highlight: 'rest_pause');

    final cards = tester
        .widgetList<SetTypeGuideCard>(find.byType(SetTypeGuideCard))
        .toList();
    expect(cards.first.info.id, 'rest_pause');
    expect(cards.first.isHighlighted, isTrue);
    expect(cards.skip(1).any((c) => c.isHighlighted), isFalse);
  });

  testWidgets('no match shows an empty state', (tester) async {
    await _pump(tester, width: 1100);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No technique matches'), findsOneWidget);
  });

  testWidgets('a phone-width window keeps one column of cards', (tester) async {
    await _pump(tester, width: 390);

    expect(_cardColumns(tester), 1);
  });

  testWidgets('a wide window puts cards in two columns', (tester) async {
    await _pump(tester, width: 1280);

    expect(_cardColumns(tester), 2);
  });

  test('every guide entry has copy for the card', () {
    final ids = <String>{};
    for (final info in SetTypeInfo.all) {
      expect(ids.add(info.id), isTrue, reason: 'duplicate id ${info.id}');
      expect(info.label, isNotEmpty);
      expect(info.fullExplanation, isNotEmpty);
      expect(info.howMeasuredInApp, isNotEmpty);
    }
    expect(ids, containsAll(<String>['drop', 'myo_reps', 'rest_pause']));
  });

  group('HxMasonry.columnsFor', () {
    test('is one column on a phone', () {
      expect(HxMasonry.columnsFor(390), 1);
    });

    test('grows with the width, up to the cap', () {
      expect(HxMasonry.columnsFor(800), 2);
      expect(HxMasonry.columnsFor(1240), 3);
      expect(HxMasonry.columnsFor(3000), 3);
      expect(HxMasonry.columnsFor(3000, maxColumns: 2), 2);
    });

    test('survives unbounded width', () {
      expect(HxMasonry.columnsFor(double.infinity), 1);
    });
  });
}
