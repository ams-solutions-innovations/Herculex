import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/presentation/widgets/empty_slot_notice.dart';

void main() {
  for (final theme in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final themeName = theme.$1;
    final themeData = theme.$2;

    testWidgets(
      '$themeName: renders the exact reason string when pattern is given',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: themeData,
              home: const Scaffold(
                body: EmptySlotNotice(
                  pattern: 'squat',
                  reason:
                      'No safe squat movement available for your '
                      'equipment/injuries.',
                ),
              ),
            ),
          ),
        );

        expect(
          find.textContaining(
            'No safe squat movement available for your equipment/injuries.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('$themeName: renders the reason verbatim with no pattern', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: EmptySlotNotice(reason: 'Custom explicit reason text.'),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Custom explicit reason text.'),
        findsOneWidget,
      );
    });

    testWidgets('$themeName: renders without throwing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeData,
            home: const Scaffold(
              body: EmptySlotNotice(pattern: 'deadlift', reason: 'ok'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }
}
