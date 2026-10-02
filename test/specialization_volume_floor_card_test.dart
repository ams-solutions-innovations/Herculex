import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/features/programs/presentation/widgets/specialization_volume_floor_card.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ProgramVolumeBreakdown breakdown,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpecializationVolumeFloorCard(breakdown: breakdown),
        ),
      ),
    );
  }

  group('SpecializationVolumeFloorCard', () {
    testWidgets(
      'renders a below-floor muscle group tinted warning with Light label',
      (tester) async {
        const breakdown = ProgramVolumeBreakdown(
          weeks: [
            WeeklyMuscleBreakdown(
              weekIndex: 0,
              weekLabel: 'Week 1',
              totalSets: 20,
              volumes: [],
            ),
          ],
          averageWeeklyVolumes: [
            MuscleVolumeEntry(muscle: 'Chest', sets: 4),
            MuscleVolumeEntry(muscle: 'Quads', sets: 16),
          ],
          averageWeeklyTotalSets: 20,
        );

        await pump(tester, breakdown);

        expect(find.text('Chest'), findsOneWidget);
        expect(find.text('4 sets'), findsOneWidget);
        expect(find.text('Light — Below the volume that usually drives progress'), findsOneWidget);

        expect(find.text('Quads'), findsOneWidget);
        expect(find.text('16 sets'), findsOneWidget);
      },
    );

    testWidgets('renders muscle labels at the inherited (regular) font weight', (
      tester,
    ) async {
      const breakdown = ProgramVolumeBreakdown(
        weeks: [
          WeeklyMuscleBreakdown(
            weekIndex: 0,
            weekLabel: 'Week 1',
            totalSets: 16,
            volumes: [],
          ),
        ],
        averageWeeklyVolumes: [MuscleVolumeEntry(muscle: 'Quads', sets: 16)],
        averageWeeklyTotalSets: 16,
      );

      await pump(tester, breakdown);

      final textWidget = tester.widget<Text>(find.text('Quads'));
      expect(textWidget.style?.fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('renders SizedBox.shrink for an empty breakdown', (
      tester,
    ) async {
      await pump(tester, ProgramVolumeBreakdown.empty);

      expect(find.byType(SpecializationVolumeFloorCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SpecializationVolumeFloorCard),
          matching: find.byType(SizedBox),
        ),
        findsOneWidget,
      );
      expect(find.text('Weekly Volume per Muscle Group'), findsNothing);
    });
  });
}
