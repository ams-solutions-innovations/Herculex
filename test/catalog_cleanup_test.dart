import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/data/local/exercise_merges.dart';
import 'package:herculex/features/workouts/presentation/equipment_variant_sheet.dart';

/// Guards the hand corrections in `tool/catalog_cleanup.py`.
///
/// The catalog's equipment and modality were derived from exercise *names* by
/// `tool/build_exercises.py`, which misfired in both directions: names carrying
/// an equipment word that meant something else ("Hammer Curl" → Hammer Strength
/// machine) and names carrying none at all, which fell through to `barbell` or
/// `other`. A wrong modality is not cosmetic — the movement layer unions its
/// members' modalities into `allowedEquipment`, so one bad row puts a nonsense
/// button in the equipment prompt for every variant of that movement.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late List<Map<String, dynamic>> catalogJson;

  setUpAll(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalogJson =
        (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
      movementsJson: File('assets/data/movements.json').readAsStringSync(),
    );
  });
  tearDownAll(() async => db.close());

  Future<ExerciseCatalogData?> bySlug(String slug) {
    return (db.select(db.exerciseCatalog)..where((t) => t.slug.equals(slug)))
        .getSingleOrNull();
  }

  group('equipment fixes', () {
    test('a hammer curl is a dumbbell, not a plate-loaded machine', () async {
      final curl = await bySlug('hammer-curl');
      expect(curl!.modality, 'dumbbell');
    });

    test('the curl movement no longer offers a machine', () async {
      // Hammer Curl was the only member contributing `machine_plate`, so the
      // prompt offered "Machine (Plate-Loaded)" on every curl in the catalog.
      final curl = await bySlug('dumbbell-curl');
      expect(EquipmentVariantSheet.optionsFor(curl!),
          isNot(contains('machine_plate')));
    });

    test('a band pushdown is loaded by a band, not a cable stack', () async {
      expect((await bySlug('band-triceps-pushdown'))!.modality, 'band');
    });

    test('no movement offers "Other" as a swap for a real modality', () async {
      // `other` covers sleds, yokes, neck harnesses and plate raises — real
      // equipment with no modality of its own. It should never appear
      // alongside barbell/dumbbell/cable as if it were a choice you could make.
      const genuinelyOther = {
        'around-the-world-core', // a weight plate
        'farmers-walk-carry', // dedicated farmer's handles
        'front-raise-isolation', // a weight plate
      };
      final movements =
          (jsonDecode(File('assets/data/movements.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>();
      for (final movement in movements) {
        final allowed =
            (movement['allowedEquipment'] as List).cast<String>();
        if (!allowed.contains('other')) continue;
        expect(
          genuinelyOther,
          contains(movement['slug']),
          reason: '"${movement['label']}" offers Other — fix the member row '
              'or add it to the allowed list here',
        );
      }
    });

    test('a bodyweight row logs reps, not weight × reps', () async {
      // Flipping modality without the logging metric leaves the logger asking
      // for a kg figure on an apparatus with no weight stack.
      for (final row in catalogJson) {
        if (row['modality'] != 'bodyweight') continue;
        expect(
          row['loggingMetric'],
          isNot('weight_reps'),
          reason: '${row['name']} is bodyweight but logs a weight',
        );
      }
    });
  });

  group('merges', () {
    test('every merged loser is gone and every winner is present', () async {
      // Keeps kExerciseMerges in step with MERGES in tool/catalog_cleanup.py:
      // a loser still in the JSON means the tool was not re-run.
      for (final merge in kExerciseMerges) {
        expect(await bySlug(merge.loser), isNull,
            reason: '${merge.loser} is still in the catalog');
        expect(await bySlug(merge.winner), isNotNull,
            reason: '${merge.winner} is missing — the merge would be skipped');
      }
    });

    test('a merged name still resolves, so program import survives', () async {
      // Program CSV import throws on an unknown name and watch sync falls back
      // to name matching, so the loser's name has to stay reachable.
      final aliases = await db.select(db.exerciseAliases).get();
      final known = aliases.map((a) => a.alias.toLowerCase()).toSet();
      for (final name in const [
        'Lateral Raise (DB)',
        'Weighted Dip',
        'Russian Twist (Weighted)',
        'Seated Rotary Torso Machine',
      ]) {
        expect(known, contains(name.toLowerCase()));
      }
    });

    test('the plain dip is the one search finds', () async {
      // "Chest Dips" normalised to "chest dip" while every other variant
      // normalised to "dip", so the movement's canonical member was whichever
      // qualified variant sorted first — searching "dip" reached Ring Dips.
      final dip = await bySlug('chest-dips');
      expect(dip!.name, 'Dip');
      expect(dip.movementSlug, 'dip-vertical-push');
      expect(dip.supportsWeightedBodyweight, isTrue,
          reason: 'Weighted Dip folded in here; added load needs a home');
    });
  });

  group('coverage', () {
    test('the plain variant of a grip family exists', () async {
      // The catalog carried five grip variations of the pull-up and the
      // pulldown, and neither of the plain movements.
      expect(await bySlug('pull-up'), isNotNull);
      expect(await bySlug('lat-pulldown'), isNotNull);
    });

    test('added rows are marked reviewed, not derived', () async {
      for (final slug in const ['pull-up', 'lat-pulldown', 'goblet-squat']) {
        expect((await bySlug(slug))!.isReviewed, isTrue);
      }
    });
  });

  group('catalog integrity', () {
    test('slugs and names are unique', () {
      final slugs = <String>{};
      final names = <String>{};
      for (final row in catalogJson) {
        expect(slugs.add(row['slug'] as String), isTrue,
            reason: 'duplicate slug ${row['slug']}');
        expect(names.add(row['name'] as String), isTrue,
            reason: 'duplicate name ${row['name']}');
      }
    });

    test('no alias shadows another exercise\'s real name', () {
      // Both the merge engine and program CSV import resolve by name, so an
      // alias that equals a different exercise makes the lookup ambiguous.
      final names = {for (final row in catalogJson) row['name'] as String};
      for (final row in catalogJson) {
        for (final alias in (row['aka'] as List).cast<String>()) {
          if (alias == row['name']) continue;
          expect(names, isNot(contains(alias)),
              reason: '${row['name']} claims "$alias", a real exercise');
        }
      }
    });

    test('every "similar" reference points at an exercise that exists', () {
      // Renames and merges leave these dangling — they are plain name strings.
      final names = {for (final row in catalogJson) row['name'] as String};
      final aliases = <String>{
        for (final row in catalogJson) ...(row['aka'] as List).cast<String>(),
      };
      final dangling = <String>{};
      for (final row in catalogJson) {
        for (final name in (row['similar'] as List).cast<String>()) {
          if (!names.contains(name) && !aliases.contains(name)) {
            dangling.add(name);
          }
        }
      }
      // The source spreadsheet's "Similar Exercises" column names plenty of
      // exercises the catalog never carried; this only guards against cleanup
      // *creating* new dangling references.
      for (final merge in kExerciseMerges) {
        expect(dangling.any((d) => d.contains(merge.loser)), isFalse);
      }
      for (final gone in const [
        'Chest Dips',
        'Lateral Raise (DB)',
        'Front Raise (DB)',
        'Weighted Dip',
        'Swiss Bar Skull Crusher',
      ]) {
        expect(dangling, isNot(contains(gone)));
      }
    });
  });
}
