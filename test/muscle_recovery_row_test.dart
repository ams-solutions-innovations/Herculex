import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/analytics/presentation/widgets/muscle_recovery_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder statusDotFinder() => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).shape == BoxShape.circle);

  testWidgets('renders the muscle name and score', (tester) async {
    await tester.pumpWidget(wrap(const MuscleRecoveryRow(muscle: 'Chest', recoveryScore: 82)));

    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
  });

  testWidgets('omits the ETA chip and status dot by default — matches the two pre-existing call sites',
      (tester) async {
    await tester.pumpWidget(wrap(const MuscleRecoveryRow(muscle: 'Quads', recoveryScore: 40)));

    expect(find.text('~18h'), findsNothing);
    expect(statusDotFinder(), findsNothing);
  });

  testWidgets('shows the ETA chip only when etaLabel is provided', (tester) async {
    await tester.pumpWidget(
      wrap(const MuscleRecoveryRow(muscle: 'Quads', recoveryScore: 40, etaLabel: '~18h')),
    );

    expect(find.text('~18h'), findsOneWidget);
  });

  testWidgets('shows a status dot only when statusDotColor is provided', (tester) async {
    await tester.pumpWidget(
      wrap(const MuscleRecoveryRow(muscle: 'Back', recoveryScore: 55, statusDotColor: Colors.red)),
    );

    expect(statusDotFinder(), findsOneWidget);
  });
}
