import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/watch_exercise_resolver.dart';

/// The failure this replaced was silent: every watch exercise the phone
/// couldn't name-match minted an `isCustom` row with `equipment: 'other'`,
/// splitting a user's history across two catalog entries for one lift. So the
/// assertions that matter are the ones about *not* falling off the end of the
/// ladder.
void main() {
  const rows = [
    ResolvableExercise(
      id: 1,
      slug: 'barbell-back-squat',
      name: 'Barbell Back Squat',
      aliases: ['Back Squat', 'Squat'],
    ),
    ResolvableExercise(
      id: 2,
      slug: 'standard-push-up',
      name: 'Standard Push-Up',
      aliases: ['Press-Up'],
    ),
    ResolvableExercise(
      id: 3,
      slug: 'lat-pulldown-wide-grip',
      name: 'Lat Pulldown (Wide Grip)',
    ),
    ResolvableExercise(id: 4, slug: 'dumbbell-curl', name: 'Dumbbell Curl'),
    // A user-made row: no slug, and its name is another row's alias.
    ResolvableExercise(id: 99, name: 'Squat'),
  ];

  final index = WatchExerciseIndex.build(rows);

  group('resolution ladder', () {
    test('catalog id wins over a name that points elsewhere', () {
      final match = index.resolve(catalogExerciseId: 1, name: 'Dumbbell Curl');
      expect(match!.exerciseId, 1);
      expect(match.source, ResolutionSource.catalogId);
    });

    test('slug resolves when the id is stale', () {
      // Reinstalled phone: ids were reassigned, slugs weren't.
      final match = index.resolve(
        catalogExerciseId: 4242,
        slug: 'standard-push-up',
        name: 'Push Ups',
      );
      expect(match!.exerciseId, 2);
      expect(match.source, ResolutionSource.slug);
    });

    test('exact name beats an alias claiming the same text', () {
      // "Squat" is both row 99's name and row 1's alias.
      final match = index.resolve(name: 'Squat');
      expect(match!.exerciseId, 99);
      expect(match.source, ResolutionSource.name);
    });

    test('alias resolves a watch name the catalog does not display', () {
      final match = index.resolve(name: 'Back Squat');
      expect(match!.exerciseId, 1);
      expect(match.source, ResolutionSource.alias);
    });

    test('punctuation drift resolves via normalization', () {
      // The watch shipped "Push-Up" where the catalog says "Standard Push-Up";
      // hyphen-vs-space is the drift that survives a name correction.
      for (final name in ['Standard push up', 'STANDARD PUSHUP']) {
        final match = index.resolve(name: name);
        expect(match?.exerciseId, 2, reason: name);
        expect(match?.source, ResolutionSource.normalizedName, reason: name);
      }
      // …including through an alias.
      expect(index.resolve(name: 'press up')!.exerciseId, 2);
    });

    test('an old build\'s synthetic equipment suffix resolves to the base row',
        () {
      // Watches that predate this change persist "Barbell Back Squat
      // (Dumbbell)" in their session store and will keep sending it.
      final match = index.resolve(name: 'Barbell Back Squat (Dumbbell)');
      expect(match!.exerciseId, 1);
      expect(match.source, ResolutionSource.normalizedName);
    });

    test('a real parenthetical qualifier is never stripped', () {
      // "(Wide Grip)" is not equipment; stripping it would silently log a
      // wide-grip pulldown against whatever row "Lat Pulldown" resolves to.
      expect(index.resolve(name: 'Lat Pulldown (Wide Grip)')!.exerciseId, 3);
      expect(stripEquipmentSuffix('Lat Pulldown (Wide Grip)'),
          'Lat Pulldown (Wide Grip)');
      expect(stripEquipmentSuffix('Squat (Barbell)'), 'Squat');
    });

    test('a genuinely unknown exercise returns null so a custom row is made',
        () {
      expect(index.resolve(name: 'Zercher Kettlebell Windmill'), isNull);
      expect(index.resolve(catalogExerciseId: 12345), isNull);
      expect(index.resolve(name: '   '), isNull);
      expect(index.resolve(), isNull);
    });

    test('an unknown slug falls through to the name rungs', () {
      final match = index.resolve(slug: 'gone-in-v20', name: 'Dumbbell Curl');
      expect(match!.exerciseId, 4);
      expect(match.source, ResolutionSource.name);
    });
  });

  group('against the shipped catalog', () {
    late WatchExerciseIndex catalogIndex;
    late List<Map<String, dynamic>> catalogRows;

    setUpAll(() {
      catalogRows = (jsonDecode(
        File('assets/data/exercises.json').readAsStringSync(),
      ) as List)
          .cast<Map<String, dynamic>>();
      catalogIndex = WatchExerciseIndex.build([
        for (var i = 0; i < catalogRows.length; i++)
          ResolvableExercise(
            id: i + 1,
            slug: catalogRows[i]['slug'] as String?,
            name: catalogRows[i]['name'] as String,
            aliases: [...?(catalogRows[i]['aka'] as List?)?.cast<String>()],
          ),
      ]);
    });

    test('every name in the catalog round-trips by name and by slug', () {
      for (var i = 0; i < catalogRows.length; i++) {
        final row = catalogRows[i];
        expect(
          catalogIndex.resolve(name: row['name'] as String)?.exerciseId,
          isNotNull,
          reason: row['name'] as String,
        );
        expect(
          catalogIndex.resolve(slug: row['slug'] as String)?.exerciseId,
          i + 1,
          reason: row['slug'] as String,
        );
      }
    });

    test('the watch cold-start defaults all resolve', () {
      // Mirrors ExerciseCatalog.defaultCategories and WorkoutStore.defaults on
      // the Wear side. If a slug is corrected there and not here, this fails
      // rather than quietly re-introducing custom-row pollution.
      const watchDefaults = [
        'barbell-bench-press',
        'incline-dumbbell-press',
        'dumbbell-fly',
        'chest-dips',
        'standard-push-up',
        'cable-fly-high-to-low',
        'conventional-deadlift',
        'barbell-row',
        'lat-pulldown',
        'pull-up',
        'seated-cable-row-v-bar',
        'single-arm-dumbbell-row',
        'face-pull',
        'barbell-back-squat',
        'romanian-deadlift',
        'leg-press',
        'leg-extension',
        'lying-leg-curl',
        'good-morning',
        'bulgarian-split-squat',
        'standing-calf-raise',
        'overhead-press',
        'dumbbell-overhead-press',
        'dumbbell-lateral-raise',
        'dumbbell-rear-delt-fly',
        'barbell-shrug',
        'dumbbell-curl',
        'hammer-curl',
        'ez-bar-preacher-curl',
        'tricep-pushdown-rope',
        'skullcrusher',
        'overhead-cable-tricep',
        'safety-bar-squat',
        'nordic-hamstring-curl',
      ];
      for (final slug in watchDefaults) {
        expect(catalogIndex.resolve(slug: slug), isNotNull, reason: slug);
      }
    });
  });
}
