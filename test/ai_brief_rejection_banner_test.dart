import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/programs/presentation/widgets/ai_brief_rejection_banner.dart';

void main() {
  for (final theme in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final themeName = theme.$1;
    final themeData = theme.$2;

    testWidgets(
      '$themeName: renders heading, body and footer verbatim',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: themeData,
              home: const Scaffold(
                body: AiBriefRejectionBanner(
                  heading: "Herculex AI suggestion couldn't be used",
                  body:
                      'The AI suggested a 6-day PPL with Max Effort, which '
                      'exceeds the safety limit.',
                  footer:
                      'Showing the recommended Smart/Guided setup instead - '
                      'you can still adjust anything below.',
                ),
              ),
            ),
          ),
        );

        expect(
          find.text("Herculex AI suggestion couldn't be used"),
          findsOneWidget,
        );
        expect(
          find.text(
            'The AI suggested a 6-day PPL with Max Effort, which exceeds '
            'the safety limit.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Showing the recommended Smart/Guided setup instead - you can '
            'still adjust anything below.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('$themeName: icon and heading use the warning token', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: AiBriefRejectionBanner(
                heading: 'Heading',
                body: 'Body',
                footer: 'Footer',
              ),
            ),
          ),
        ),
      );

      final context = tester.element(find.byType(AiBriefRejectionBanner));
      final expectedWarning = context.hx.warning;

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.warning_amber_rounded),
      );
      expect(icon.color, expectedWarning);

      final headingText = tester.widget<Text>(find.text('Heading'));
      expect(headingText.style?.color, expectedWarning);
      expect(headingText.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('$themeName: renders without throwing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: AiBriefRejectionBanner(
                heading: 'Heading',
                body: 'Body',
                footer: 'Footer',
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }
}
