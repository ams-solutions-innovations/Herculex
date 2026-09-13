import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
    await db.delete(db.exerciseMuscles).go();
    await db.delete(db.exerciseAliases).go();
    await db.delete(db.exerciseCatalog).go();
  });

  tearDown(() => db.close());

  Future<void> importBundledCatalog() => ExerciseImporter.runFromJson(
    db,
    File('assets/data/exercises.json').readAsStringSync(),
    movementsJson: File('assets/data/movements.json').readAsStringSync(),
    programmingMetadataJson: File(
      'assets/data/exercise_programming_metadata.json',
    ).readAsStringSync(),
  );

  test(
    'persists explicitly curated advanced calisthenics and specialty bars',
    () async {
      await importBundledCatalog();
      final catalog = await db.select(db.exerciseCatalog).get();
      ExerciseCatalogData bySlug(String slug) =>
          catalog.singleWhere((exercise) => exercise.slug == slug);

      for (final slug in ['ring-muscle-up', 'full-planche', 'hefesto']) {
        final exercise = bySlug(slug);
        expect(exercise.programmingDifficulty, 'advanced', reason: slug);
        expect(exercise.programmingCommonness, 'specialty', reason: slug);
        expect(exercise.technicalEligibility, 'manual_only', reason: slug);
        expect(
          jsonDecode(exercise.allowedTrainingStyles!),
          contains('calisthenics'),
        );
      }

      for (final slug in [
        'spoto-press',
        'swiss-bar-bench-press',
        'safety-bar-squat',
        'board-press',
        'pin-press',
      ]) {
        final exercise = bySlug(slug);
        expect(exercise.programmingDifficulty, 'advanced', reason: slug);
        expect(exercise.programmingCommonness, 'specialty', reason: slug);
        expect(exercise.technicalEligibility, 'manual_only', reason: slug);
      }
    },
  );

  test(
    'persists curated basic profiles but leaves missing metadata safe',
    () async {
      await importBundledCatalog();
      final catalog = await db.select(db.exerciseCatalog).get();
      ExerciseCatalogData bySlug(String slug) =>
          catalog.singleWhere((exercise) => exercise.slug == slug);

      final squat = bySlug('barbell-back-squat');
      expect(squat.programmingDifficulty, 'novice');
      expect(squat.programmingCommonness, 'basic');
      expect(squat.technicalEligibility, 'automatic');
      expect(
        jsonDecode(squat.allowedTrainingStyles!),
        containsAll(['weightlifting', 'basic']),
      );
      expect(jsonDecode(squat.disciplines!), contains('weights'));
      expect(squat.competitionAnchor, 'squat');
      expect(squat.scalingGroup, 'squat');
      expect(squat.scalingOrder, 3);
      expect(
        jsonDecode(squat.specializationTags!),
        containsAll(['squat-bottom', 'squat-mid', 'squat-lockout']),
      );

      final rmu = bySlug('ring-muscle-up');
      expect(rmu.programmingDifficulty, 'advanced');
      expect(rmu.programmingCommonness, 'specialty');
      expect(rmu.technicalEligibility, 'manual_only');
      expect(jsonDecode(rmu.disciplines!), contains('calisthenics'));
      expect(
        jsonDecode(rmu.prerequisiteSlugs!),
        containsAll(['pull-up', 'chest-dips']),
      );
      expect(rmu.scalingGroup, 'vertical_pull');
      expect(rmu.scalingOrder, 7);

      // The source intentionally does not use heuristic blanket labelling.
      // An unlisted legacy exercise is therefore never automatically selected.
      final uncurated = bySlug('steinborn-squat');
      expect(uncurated.programmingDifficulty, 'advanced');
      expect(uncurated.programmingCommonness, 'manualOnly');
      expect(uncurated.technicalEligibility, 'manual_only');
      expect(jsonDecode(uncurated.allowedTrainingStyles!), isEmpty);
      expect(jsonDecode(uncurated.disciplines!), isEmpty);
      expect(jsonDecode(uncurated.prerequisiteSlugs!), isEmpty);
      expect(uncurated.scalingGroup, isNull);
      expect(uncurated.scalingOrder, isNull);
    },
  );

  test(
    'metadata overlay is idempotent and rejects unknown values safely',
    () async {
      const exercises = '''[
      {"slug":"curated","name":"Curated","primaryMuscle":"Chest","equipment":"Barbell","movementPattern":"horizontal_push","modality":"barbell"},
      {"slug":"unknown","name":"Unknown","primaryMuscle":"Chest","equipment":"Barbell","movementPattern":"horizontal_push","modality":"barbell"}
    ]''';
      const metadata = '''{
      "exercises": {
        "curated": {"difficulty":"novice","commonness":"basic","allowedTrainingStyles":["weightlifting","not-a-style"],"technicalEligibility":"automatic"},
        "unknown": {"difficulty":"expert","commonness":"rare","allowedTrainingStyles":["not-a-style"],"technicalEligibility":"unsafe"}
      }
    }''';

      await ExerciseImporter.runFromJson(
        db,
        exercises,
        programmingMetadataJson: metadata,
      );
      await ExerciseImporter.runFromJson(
        db,
        exercises,
        programmingMetadataJson: metadata,
      );

      final catalog = await db.select(db.exerciseCatalog).get();
      expect(catalog, hasLength(2));
      final curated = catalog.singleWhere(
        (exercise) => exercise.slug == 'curated',
      );
      expect(curated.programmingDifficulty, 'novice');
      expect(curated.programmingCommonness, 'basic');
      expect(curated.technicalEligibility, 'automatic');
      expect(jsonDecode(curated.allowedTrainingStyles!), ['weightlifting']);

      final unknown = catalog.singleWhere(
        (exercise) => exercise.slug == 'unknown',
      );
      expect(unknown.programmingDifficulty, 'advanced');
      expect(unknown.programmingCommonness, 'manualOnly');
      expect(unknown.technicalEligibility, 'manual_only');
      expect(jsonDecode(unknown.allowedTrainingStyles!), isEmpty);
      expect(jsonDecode(unknown.disciplines!), isEmpty);
      expect(jsonDecode(unknown.prerequisiteSlugs!), isEmpty);
      expect(unknown.scalingGroup, isNull);
      expect(unknown.scalingOrder, isNull);
    },
  );
}
