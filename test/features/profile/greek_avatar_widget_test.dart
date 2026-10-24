import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_picker_sheet.dart';

void main() {
  testWidgets('GreekAvatarBadge renders initials when avatarId is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GreekAvatarBadge(avatarId: null, name: 'Martin', size: 56),
        ),
      ),
    );

    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('GreekAvatarBadge renders avatar image when avatarId is valid', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GreekAvatarBadge(
            avatarId: 'hercules',
            name: 'Martin',
            size: 56,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'GreekAvatarPickerSheet displays English categories and selects avatar',
    (tester) async {
      GreekAvatarSelectionResult? selection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selection = await GreekAvatarPickerSheet.show(
                    context,
                    currentAvatarId: 'hercules',
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Profile Picture'), findsOneWidget);
      expect(
        find.text('Greek gods, titans & legends of Olympus'),
        findsOneWidget,
      );
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Olympian Gods'), findsOneWidget);
      expect(find.text('Demigods'), findsOneWidget);
      expect(find.text('Titans'), findsOneWidget);
      expect(find.text('Legends'), findsOneWidget);

      // Tap "Select Hercules" CTA
      await tester.tap(find.text('Select Hercules'));
      await tester.pumpAndSettle();

      expect(selection?.avatarId, 'hercules');
    },
  );
}
