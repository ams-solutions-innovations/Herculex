import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_picker_sheet.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );
}

void main() {
  group('GreekAvatarBadge', () {
    testWidgets('renders fallback initial when avatarId is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GreekAvatarBadge(
            avatarId: null,
            fallbackName: 'Hercules User',
            size: 64,
          ),
        ),
      );

      expect(find.text('H'), findsOneWidget);
    });

    testWidgets('triggers onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          GreekAvatarBadge(
            avatarId: 'zeus',
            fallbackName: 'Zeus',
            size: 64,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(GreekAvatarBadge));
      expect(tapped, isTrue);
    });
  });

  group('GreekAvatarPickerSheet', () {
    testWidgets('displays title and categories', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const GreekAvatarPickerSheet(currentAvatarId: 'hercules')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Izberi profilno sliko'), findsOneWidget);
      expect(
        find.text('Grški bogovi, titani in legende Olimpa'),
        findsOneWidget,
      );
      expect(find.text('Vsi (${GreekAvatar.all.length})'), findsOneWidget);
      expect(find.textContaining('Bogovi'), findsWidgets);
      expect(find.textContaining('Titani'), findsWidgets);
      expect(find.textContaining('Demi-bogovi'), findsWidgets);
      expect(find.textContaining('Legende'), findsWidgets);
    });

    testWidgets('tapping an avatar selects it and updates preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const GreekAvatarPickerSheet(currentAvatarId: 'hercules')),
      );
      await tester.pumpAndSettle();

      // Tap on Zeus in the grid
      final zeusText = find.text('Zeus');
      expect(zeusText, findsWidgets);

      await tester.tap(zeusText.last);
      await tester.pumpAndSettle();

      expect(find.text('Izberi Zeus'), findsOneWidget);
    });
  });
}
