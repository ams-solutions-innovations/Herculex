import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/calisthenics_providers.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';
import 'package:herculex/features/workouts/presentation/sheets/calisthenics_level_sheet.dart';

ExerciseCatalogData _exercise(String slug) => ExerciseCatalogData(
  id: 1,
  name: slug,
  slug: slug,
  primaryMuscle: 'Back',
  equipment: 'Bodyweight',
  mechanics: 'compound',
  force: 'pull',
  plane: 'vertical',
  defaultRestSeconds: 120,
  isCustom: false,
  category: 'calisthenics',
  modality: 'bodyweight',
  cnsScore: 4,
  recoveryImpact: 2,
  loggingMetric: 'reps',
  supportsWeightedBodyweight: true,
  isReviewed: true,
);

void main() {
  testWidgets(
    'recommended next level requires technique confirmation and returns targets',
    (tester) async {
      final path = calisthenicsPathFor('pull-up')!;
      final recommendation = CalisthenicsRecommendation(
        path: path,
        current: path.levels[1],
        target: path.levels[2],
        ready: true,
        successes: 2,
        value: 5,
        load: 1.25,
        reason: 'Ready to try weighted.',
      );
      CalisthenicsPick? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calisthenicsRecommendationsProvider.overrideWith(
              (ref) => Stream.value({'pull-up': recommendation}),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await CalisthenicsLevelSheet.show(context, path, [
                      _exercise('pull-up'),
                    ]);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level III · Weighted'));
      await tester.pumpAndSettle();
      expect(find.text('Try the next level?'), findsOneWidget);
      expect(result, null);
      await tester.tap(find.text('Keep current level'));
      await tester.pumpAndSettle();
      expect(result, null);
      await tester.tap(find.text('Level III · Weighted'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, try it'));
      await tester.pumpAndSettle();
      expect(result!.level.variant, 'weighted');
      expect(result!.value, 5);
      expect(result!.load, 1.25);
    },
  );

  testWidgets('kipping is visible as a separate technique branch', (
    tester,
  ) async {
    final path = calisthenicsPathFor('strict-muscle-up')!;
    final recommendation = CalisthenicsProgression.recommend(
      path,
      [],
      DateTime(2026, 10, 14),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calisthenicsRecommendationsProvider.overrideWith(
            (ref) => Stream.value({path.id: recommendation}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CalisthenicsLevelSheet(
              path: path,
              catalog: [
                _exercise('strict-muscle-up'),
                _exercise('kipping-muscle-up'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Technique branch · does not unlock strict strength levels'),
      findsOneWidget,
    );
    expect(find.textContaining('Recommended'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
