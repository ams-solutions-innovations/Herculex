import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/programs/presentation/widgets/ai_day_rationale_card.dart';

void main() {
  for (final theme in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final themeName = theme.$1;
    final themeData = theme.$2;

    testWidgets(
      '$themeName: renders the rationale verbatim plus the fixed heading '
      'and icon',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: themeData,
              home: const Scaffold(
                body: AiDayRationaleCard(
                  rationale:
                      'Because this day follows two heavy pull sessions, '
                      "it's programmed as active recovery.",
                ),
              ),
            ),
          ),
        );

        expect(find.text('Why this day'), findsOneWidget);
        expect(
          find.text(
            'Because this day follows two heavy pull sessions, it\'s '
            'programmed as active recovery.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      },
    );

    testWidgets('$themeName: icon and heading use the primary token', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: AiDayRationaleCard(rationale: 'Because...'),
            ),
          ),
        ),
      );

      final context = tester.element(find.byType(AiDayRationaleCard));
      final expectedPrimary = context.hx.primary;

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.auto_awesome_rounded),
      );
      expect(icon.color, expectedPrimary);

      final headingText = tester.widget<Text>(find.text('Why this day'));
      expect(headingText.style?.color, expectedPrimary);
      expect(headingText.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('$themeName: renders without throwing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: AiDayRationaleCard(rationale: 'ok'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }
}
