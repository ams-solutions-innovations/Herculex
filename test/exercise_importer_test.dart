import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/presentation/exercise_picker_sheet.dart';

final _sample = jsonEncode([
  {
    'name': 'Conventional Deadlift',
    'aka': ['Deads', 'Deadlift'],
    'category': 'powerlifting',
    'movementPattern': 'hinge',
    'modality': 'barbell',
    'equipment': 'Barbell',
    'primaryMuscle': 'Hamstrings',
    'primaryMuscles': ['Hamstrings', 'Glutes'],
    'secondaryMuscles': ['Erectors'],
    'stabilizers': ['Forearms'],
    'cnsScore': 9,
    'recoveryImpact': 5,
    'loggingMetric': 'weight_reps',
    'supportsWeightedBodyweight': false,
    'defaultRestSeconds': 240,
    'derived': true,
  },
  {
    'name': 'Lateral Raise',
    'aka': ['Side Raise'],
    'category': 'hypertrophy',
    'movementPattern': 'isolation',
    'modality': 'dumbbell',
    'equipment': 'Dumbbell',
    'primaryMuscle': 'Shoulders',
    'primaryMuscles': ['Side Delts'],
    'secondaryMuscles': [],
    'stabilizers': [],
    'cnsScore': 2,
    'recoveryImpact': 1,
    'loggingMetric': 'weight_reps',
    'supportsWeightedBodyweight': false,
    'defaultRestSeconds': 60,
    'derived': true,
  },
  {
    'name': 'Push-Up',
    'aka': ['Push Up', 'Press Up'],
    'category': 'calisthenics',
    'movementPattern': 'horizontal_push',
    'modality': 'bodyweight',
    'equipment': 'Bodyweight',
    'primaryMuscle': 'Chest',
    'primaryMuscles': ['Chest'],
    'secondaryMuscles': ['Triceps', 'Front Delts'],
    'stabilizers': ['Core'],
    'cnsScore': 3,
    'recoveryImpact': 2,
    'loggingMetric': 'reps',
    'supportsWeightedBodyweight': true,
    'defaultRestSeconds': 90,
    'derived': true,
  },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Clear whatever onCreate seeded so we measure the importer precisely.
    await db.delete(db.exerciseMuscles).go();
    await db.delete(db.exerciseAliases).go();
    await db.delete(db.exerciseCatalog).go();
  });

  tearDown(() async => db.close());

  test('imports exercises with muscles and aliases', () async {
    await ExerciseImporter.runFromJson(db, _sample);

    final catalog = await db.select(db.exerciseCatalog).get();
    expect(catalog, hasLength(3));

    final deadlift = catalog.firstWhere(
      (e) => e.name == 'Conventional Deadlift',
    );
    expect(deadlift.cnsScore, 9);
    expect(deadlift.modality, 'barbell');
    expect(deadlift.isReviewed, isFalse); // derived ⇒ unreviewed
    expect(deadlift.primaryMuscle, 'Hamstrings'); // coarse legacy column

    final muscles = await (db.select(
      db.exerciseMuscles,
    )..where((t) => t.exerciseId.equals(deadlift.id))).get();
    expect(muscles.where((m) => m.role == 'primary'), hasLength(2));
    expect(muscles.where((m) => m.role == 'secondary'), hasLength(1));
    expect(muscles.where((m) => m.role == 'stabilizer'), hasLength(1));

    final aliases = await db.select(db.exerciseAliases).get();
    expect(aliases.map((a) => a.alias), containsAll(['Deads', 'Deadlift']));
  });

  test(
    'is idempotent — re-running preserves ids and does not duplicate',
    () async {
      await ExerciseImporter.runFromJson(db, _sample);
      final firstId =
          (await db.select(db.exerciseCatalog).get()).map((e) => e.id).toList()
            ..sort();

      await ExerciseImporter.runFromJson(db, _sample);
      final after = await db.select(db.exerciseCatalog).get();
      final secondId = after.map((e) => e.id).toList()..sort();

      expect(after, hasLength(3), reason: 'no duplicate rows on re-import');
      expect(secondId, firstId, reason: 'row ids are preserved');

      final muscles = await db.select(db.exerciseMuscles).get();
      // 2 + 1 + 1 (deadlift) + 1 (lateral raise) + 1 + 2 + 1 (push-up) = 9.
      expect(muscles, hasLength(9));
    },
  );

  test(
    'alias search returns the parent exercise (canonical name shown)',
    () async {
      await ExerciseImporter.runFromJson(db, _sample);
      final repo = WorkoutsRepository(db, const SystemClock());

      final byAlias = await repo.watchExercises(query: 'Deads').first;
      expect(byAlias, hasLength(1));
      expect(byAlias.first.name, 'Conventional Deadlift');

      final bySideRaise = await repo.watchExercises(query: 'Side Raise').first;
      expect(bySideRaise.single.name, 'Lateral Raise');
    },
  );

  test(
    'normalized search handles hyphens, spaces, and compact names',
    () async {
      await ExerciseImporter.runFromJson(db, _sample);
      final repo = WorkoutsRepository(db, const SystemClock());

      for (final query in ['push-up', 'push up', 'pushup', 'push ups']) {
        final matches = await repo.watchExercises(query: query).first;
        expect(matches.map((e) => e.name), contains('Push-Up'));
      }
    },
  );

  test('search and filters include granular muscles and mechanics', () async {
    await ExerciseImporter.runFromJson(db, _sample);
    final repo = WorkoutsRepository(db, const SystemClock());

    final byGranularMuscle = await repo
        .watchExercises(category: 'Side Delts')
        .first;
    expect(byGranularMuscle.single.name, 'Lateral Raise');

    final byCompound = await repo.watchExercises(category: 'Compound').first;
    expect(
      byCompound.map((e) => e.name),
      containsAll(['Conventional Deadlift', 'Push-Up']),
    );
    expect(byCompound.map((e) => e.name), isNot(contains('Lateral Raise')));

    final byLegs = await repo.watchExercises(category: 'Legs').first;
    expect(byLegs.map((e) => e.name), contains('Conventional Deadlift'));
  });

  test(
    'exercise picker exposes Recent first and sorts recent matches first',
    () async {
      await ExerciseImporter.runFromJson(db, _sample);
      final catalog = await db.select(db.exerciseCatalog).get();
      final deadlift = catalog.firstWhere(
        (e) => e.name == 'Conventional Deadlift',
      );

      expect(exercisePickerFilterChips.first, 'Recent');
      expect(
        exercisePickerFilterChips,
        containsAll(['Compound', 'Isolation', 'Side Delts', 'Calves']),
      );

      final sorted = sortRecentExercisesFirst(catalog, {deadlift.id});
      expect(sorted.first.name, 'Conventional Deadlift');
      expect(
        sorted.skip(1).map((e) => e.name),
        orderedEquals(['Lateral Raise', 'Push-Up']),
      );
    },
  );

  test('the real generated catalog asset imports cleanly', () async {
    final json = File('assets/data/exercises.json').readAsStringSync();
    await ExerciseImporter.runFromJson(db, json);

    final catalog = await db.select(db.exerciseCatalog).get();
    expect(
      catalog.length,
      greaterThan(390),
      reason: 'full 398-exercise dataset should load',
    );
    // Every row carries a derived CNS score and primary muscle.
    expect(catalog.every((e) => e.cnsScore >= 1 && e.cnsScore <= 10), isTrue);
    expect(catalog.every((e) => e.primaryMuscle.isNotEmpty), isTrue);
    // Granular muscle involvement was written for the catalog.
    final muscles = await db.select(db.exerciseMuscles).get();
    expect(muscles.length, greaterThan(catalog.length));
    for (final exercise in catalog) {
      expect(
        muscles.any((m) => m.exerciseId == exercise.id && m.role == 'primary'),
        isTrue,
        reason: '${exercise.name} should have at least one primary muscle',
      );
      expect(
        {'compound', 'isolation'},
        contains(exercise.mechanics),
        reason: '${exercise.name} should be filterable by mechanics',
      );
    }

    final repo = WorkoutsRepository(db, const SystemClock());
    final deads = await repo.watchExercises(query: 'Deads').first;
    expect(deads.any((e) => e.name == 'Conventional Deadlift'), isTrue);
  });

  test(
    'real catalog keeps audited equipment and arm-isolation classifications',
    () async {
      final json = File('assets/data/exercises.json').readAsStringSync();
      await ExerciseImporter.runFromJson(db, json);
      final catalog = await db.select(db.exerciseCatalog).get();

      ExerciseCatalogData byName(String name) =>
          catalog.firstWhere((e) => e.name == name);

      final trapJump = byName('Trap Bar Jump Squat');
      expect(trapJump.equipment, 'Trap Bar');
      expect(trapJump.modality, 'barbell');
      expect(trapJump.loggingMetric, 'weight_reps');
      expect(trapJump.supportsWeightedBodyweight, isFalse);

      final muscles = await db.select(db.exerciseMuscles).get();
      List<ExerciseMuscleData> musclesFor(String name) {
        final exercise = byName(name);
        return muscles.where((m) => m.exerciseId == exercise.id).toList();
      }

      expect(
        musclesFor(
          'Ring Bicep Curl',
        ).where((m) => m.role == 'primary').map((m) => m.muscle),
        orderedEquals(['Biceps']),
      );
      expect(
        musclesFor(
          'TRX Bicep Curl',
        ).where((m) => m.role == 'primary').map((m) => m.muscle),
        orderedEquals(['Biceps']),
      );
      expect(
        musclesFor(
          'Ring Triceps Extension',
        ).where((m) => m.role == 'primary').map((m) => m.muscle),
        orderedEquals(['Triceps']),
      );
      expect(
        musclesFor(
          'TRX Triceps Extension',
        ).where((m) => m.role == 'primary').map((m) => m.muscle),
        orderedEquals(['Triceps']),
      );
    },
  );

  test(
    'real catalog search covers natural naming and filter variants',
    () async {
      final json = File('assets/data/exercises.json').readAsStringSync();
      await ExerciseImporter.runFromJson(db, json);
      final repo = WorkoutsRepository(db, const SystemClock());

      Future<void> expectAny(
        String label,
        Future<List<ExerciseCatalogData>> future,
        bool Function(ExerciseCatalogData exercise) predicate,
      ) async {
        final matches = await future;
        expect(
          matches.any(predicate),
          isTrue,
          reason: '$label should return a matching exercise',
        );
      }

      await expectAny(
        'pushup compact search',
        repo.watchExercises(query: 'pushup').first,
        (e) => e.name == 'Standard Push-Up',
      );
      await expectAny(
        'push up spaced search',
        repo.watchExercises(query: 'push up').first,
        (e) => e.name == 'Standard Push-Up',
      );
      await expectAny(
        'push-up hyphenated search',
        repo.watchExercises(query: 'push-up').first,
        (e) => e.name == 'Standard Push-Up',
      );
      await expectAny(
        'pullup compact search',
        repo.watchExercises(query: 'pullup').first,
        (e) => e.name.contains('Pull-Up'),
      );
      await expectAny(
        'side delt muscle filter',
        repo.watchExercises(category: 'Side Delts').first,
        (e) => e.name == 'Lateral Raise (DB)',
      );
      await expectAny(
        'compound mechanics filter',
        repo.watchExercises(category: 'Compound').first,
        (e) => e.name == 'Barbell Bench Press',
      );
      await expectAny(
        'isolation mechanics filter',
        repo.watchExercises(category: 'Isolation').first,
        (e) => e.name == 'Lateral Raise (DB)',
      );
      await expectAny(
        'natural legs group filter',
        repo.watchExercises(category: 'Legs').first,
        (e) => e.name == 'Barbell Back Squat',
      );
      await expectAny(
        'machine chest multi-term search',
        repo.watchExercises(query: 'Machine Chest').first,
        (e) => e.name == 'Machine Incline Press',
      );
      await expectAny(
        'slovenian machine chest multi-term search',
        repo.watchExercises(query: 'masina chest').first,
        (e) => e.name == 'Machine Incline Press',
      );
      await expectAny(
        'cable curl multi-term search',
        repo.watchExercises(query: 'Cable Curl').first,
        (e) => e.name == 'Cable Bicep Curl',
      );
      await expectAny(
        'machine pull multi-term search',
        repo.watchExercises(query: 'Machine Pull').first,
        (e) => e.name == 'Machine High Row',
      );
      await expectAny(
        'dumbbell push multi-term search',
        repo.watchExercises(query: 'Dumbbell Push').first,
        (e) => e.name == 'Dumbbell Bench Press',
      );
    },
  );

  test('equipment variants of one movement share a movementFamily', () async {
    final json = File('assets/data/exercises.json').readAsStringSync();
    await ExerciseImporter.runFromJson(db, json);
    final catalog = await db.select(db.exerciseCatalog).get();

    ExerciseCatalogData byName(String n) =>
        catalog.firstWhere((e) => e.name == n);

    final inclineFamilies = {
      byName('Incline Barbell Bench').movementFamily,
      byName('Incline Dumbbell Press').movementFamily,
      byName('Machine Incline Press').movementFamily,
      byName('Swiss Bar Incline Press').movementFamily,
    };
    expect(
      inclineFamilies,
      hasLength(1),
      reason: 'all four incline presses collapse to one family',
    );
    expect(inclineFamilies.single, isNotNull);

    // Flat bench is a different movement and must NOT merge with incline.
    expect(
      byName('Barbell Bench Press').movementFamily,
      isNot(inclineFamilies.single),
      reason: 'incline and flat press are distinct families',
    );
  });
}
