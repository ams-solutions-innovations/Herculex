import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/widgets/set_type_menu.dart';

void main() {
  group('isAdvancedTechniqueAllowed', () {
    test('returns false for SlotRole.main even when programAllows is true', () {
      expect(isAdvancedTechniqueAllowed(SlotRole.main, true), isFalse);
    });

    test('returns false for SlotRole.main when programAllows is false', () {
      expect(isAdvancedTechniqueAllowed(SlotRole.main, false), isFalse);
    });

    test('returns false for a non-main role when programAllows is false', () {
      expect(isAdvancedTechniqueAllowed(SlotRole.accessory, false), isFalse);
      expect(isAdvancedTechniqueAllowed(SlotRole.supplemental, false), isFalse);
      expect(isAdvancedTechniqueAllowed(SlotRole.isolation, false), isFalse);
      expect(isAdvancedTechniqueAllowed(SlotRole.conditioning, false), isFalse);
    });

    test('returns true for a non-main role only when programAllows is true', () {
      expect(isAdvancedTechniqueAllowed(SlotRole.accessory, true), isTrue);
      expect(isAdvancedTechniqueAllowed(SlotRole.supplemental, true), isTrue);
      expect(isAdvancedTechniqueAllowed(SlotRole.isolation, true), isTrue);
      expect(isAdvancedTechniqueAllowed(SlotRole.conditioning, true), isTrue);
    });
  });

  group('SetTypeMenu item filtering', () {
    testWidgets(
      'hides hypertrophy items and amrap when allowAdvancedTechniques is false',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SetTypeMenu(
                current: SetType.standard,
                allowAdvancedTechniques: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Hypertrophy/intensity techniques must be entirely absent.
        expect(find.text('Drop Set'), findsNothing);
        expect(find.text('Rest-Pause'), findsNothing);
        expect(find.text('Myo Reps'), findsNothing);

        // AMRAP (the timed-category item that's also gated) must be absent.
        expect(find.text('AMRAP'), findsNothing);

        // Other timed items remain, since only `amrap` is gated within `timed`.
        expect(find.text('EMOM'), findsOneWidget);
        expect(find.text('For Time'), findsOneWidget);
      },
    );

    testWidgets(
      'shows hypertrophy items and amrap when allowAdvancedTechniques is true',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SetTypeMenu(
                current: SetType.standard,
                allowAdvancedTechniques: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Drop Set'), findsOneWidget);
        expect(find.text('AMRAP'), findsOneWidget);
        expect(find.text('EMOM'), findsOneWidget);
        expect(find.text('For Time'), findsOneWidget);
      },
    );
  });
}
