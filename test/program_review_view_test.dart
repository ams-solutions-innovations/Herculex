import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/presentation/sheets/exercise_replacement_sheet.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ExerciseCatalogData exercise() => const ExerciseCatalogData(
    id: 1,
    name: 'Barbell Bench Press',
    primaryMuscle: 'Chest',
    equipment: 'barbell',
    mechanics: 'compound',
    force: 'push',
    plane: 'horizontal',
    defaultRestSeconds: 120,
    isCustom: false,
    category: 'strength',
    modality: 'strength',
    cnsScore: 4,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: false,
    isReviewed: true,
    programmingDifficulty: 'intermediate',
    programmingCommonness: 'basic',
    allowedTrainingStyles: '[]',
    technicalEligibility: 'automatic',
  );

  Widget harness(ThemeData theme) => ProviderScope(
    overrides: [recentExerciseIdsProvider.overrideWith((ref) async => <int>{})],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ExerciseReplacementSheet(
            current: exercise(),
            candidates: const [],
          ),
        ),
      ),
    ),
  );

  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    testWidgets('exercise replacement sheet has an opaque Hx surface', (
      tester,
    ) async {
      await tester.pumpWidget(harness(theme));

      expect(find.byType(HxSheet), findsOneWidget);
      expect(find.text('Choose a replacement'), findsOneWidget);

      final sheetMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HxSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheetMaterial.color, theme.colorScheme.surfaceContainer);
      expect(sheetMaterial.color, isNot(Colors.transparent));
    });

    testWidgets('exercise replacement defaults to the recommended wave scope', (
      tester,
    ) async {
      await tester.pumpWidget(harness(theme));

      expect(find.text('This wave · Recommended'), findsOneWidget);
      expect(find.text('This and future waves'), findsOneWidget);
      expect(find.text('Entire block'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'This wave · Recommended'),
            )
            .selected,
        isTrue,
      );
    });
  }

  group('ProgramReviewView empty-slot notices', () {
    late AppDatabase db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() => db.close());

    Future<int> seedProgram({required bool includeEmptySlot}) async {
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Test Program'));
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Lower',
              slotLabel: const Value('Lower'),
            ),
          );
      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Barbell Back Squat',
              primaryMuscle: 'Quads',
              equipment: 'barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
            ),
          );

      final filledSlotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'lower-main',
              daySlotLabel: 'Lower',
              orderIndex: 0,
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: filledSlotId,
              weekIndex: 0,
              chosenExerciseId: Value(exerciseId),
              status: 'filled',
              rationale: 'Best available option.',
            ),
          );

      if (includeEmptySlot) {
        final emptySlotId = await db
            .into(db.programExerciseSlots)
            .insert(
              ProgramExerciseSlotsCompanion.insert(
                programId: programId,
                slotKey: 'lower-accessory',
                daySlotLabel: 'Lower',
                orderIndex: 1,
              ),
            );
        await db
            .into(db.programSlotExplanations)
            .insert(
              ProgramSlotExplanationsCompanion.insert(
                slotId: emptySlotId,
                weekIndex: 0,
                status: 'empty',
                rationale:
                    'No safe squat movement available for your equipment/injuries.',
              ),
            );
      }

      return programId;
    }

    Widget harness(int programId) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProgramReviewView(programId: programId),
      ),
    );

    testWidgets(
      'renders EmptySlotNotice with the planner rationale for an empty slot',
      (tester) async {
        final programId = await seedProgram(includeEmptySlot: true);

        await tester.pumpWidget(harness(programId));
        // HxScreenShell owns a repeating ambient animation, so pumpAndSettle
        // is intentionally inappropriate here. Two frames are enough for the
        // async _load() to complete.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.textContaining('No safe squat movement available'),
          findsOneWidget,
        );
        expect(find.text('Barbell Back Squat'), findsOneWidget);
      },
    );

    testWidgets(
      'a day with only filled slots renders no EmptySlotNotice',
      (tester) async {
        final programId = await seedProgram(includeEmptySlot: false);

        await tester.pumpWidget(harness(programId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.textContaining('No safe squat movement available'),
          findsNothing,
        );
        expect(find.text('Barbell Back Squat'), findsOneWidget);
        expect(
          find.text('No exercises have been added for this day.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a metcon row renders the decoded AMRAP summary, not the placeholder',
      (tester) async {
        final programId = await db
            .into(db.programs)
            .insert(ProgramsCompanion.insert(name: 'Test Program'));
        final weekId = await db
            .into(db.programWeeks)
            .insert(
              ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
            );
        final dayId = await db
            .into(db.programDays)
            .insert(
              ProgramDaysCompanion.insert(
                programWeekId: weekId,
                dayOfWeek: 1,
                name: 'Metcon',
                slotLabel: const Value('Metcon'),
              ),
            );
        final exerciseId = await db
            .into(db.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                name: 'Wall Ball',
                primaryMuscle: 'Quads',
                equipment: 'medicine_ball',
                mechanics: 'compound',
                force: 'push',
                plane: 'axial',
              ),
            );

        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: exerciseId,
                orderIndex: 0,
                sessionSegment: const Value('metcon'),
                targetSets: const Value(1),
                targetRepsMin: const Value(1),
                targetRepsMax: const Value(1),
                prescriptionCodecJson: Value(
                  SlotPrescriptionCodec.encode(
                    const SlotPrescription(
                      name: 'Metcon',
                      segments: [
                        WorkSegment(
                          sets: 1,
                          repsMin: 1,
                          setType: SetType.amrap,
                          meta: {'capSeconds': 450},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );

        await tester.pumpWidget(harness(programId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('AMRAP'), findsOneWidget);
        expect(find.textContaining('1 sets'), findsNothing);
      },
    );
  });
}
