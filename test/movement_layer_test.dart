import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/workouts/presentation/equipment_variant_sheet.dart';
import 'package:herculex/features/workouts/presentation/exercise_picker_sheet.dart';

import 'support/test_database.dart';

/// The movement layer is what turns "Barbell Row / Dumbbell Row / Cable Row"
/// into one picker entry, and what stops the equipment prompt offering
/// physically impossible swaps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUpAll(() async {
    db = await openTestDatabase();
    // forTesting cannot read rootBundle, so feed both assets directly.
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
      movementsJson: File('assets/data/movements.json').readAsStringSync(),
    );
  });
  tearDownAll(() async => db.close());

  Future<ExerciseCatalogData> bySlug(String slug) {
    return (db.select(db.exerciseCatalog)..where((t) => t.slug.equals(slug)))
        .getSingle();
  }

  group('equipment options', () {
    test('a single-equipment exercise offers no swap at all', () async {
      // The reported bug: a seated hamstring curl exists on exactly one
      // machine, yet the prompt offered Barbell, Dumbbell and Smith Machine.
      final legCurl = await bySlug('seated-leg-curl');
      final options = EquipmentVariantSheet.optionsFor(legCurl);

      expect(options, isNot(contains('smith')));
      expect(options, isNot(contains('barbell')));
      expect(options, isNot(contains('dumbbell')));
      expect(options, isNot(contains('kettlebell')));
      expect(
        options,
        hasLength(1),
        reason: 'one option means show() skips the sheet entirely',
      );
    });

    test('a genuinely multi-equipment movement still offers its swaps',
        () async {
      final bench = await bySlug('barbell-bench-press');
      final options = EquipmentVariantSheet.optionsFor(bench);

      expect(options.first, 'barbell', reason: 'catalog modality leads');
      expect(options, containsAll(['dumbbell', 'smith']));
    });

    test('every offered option is one an exercise in the movement uses',
        () async {
      final catalog = await db.select(db.exerciseCatalog).get();
      final byMovement = <String, Set<String>>{};
      for (final e in catalog) {
        final slug = e.movementSlug;
        if (slug != null) {
          byMovement.putIfAbsent(slug, () => <String>{}).add(e.modality);
        }
      }

      for (final e in catalog) {
        final raw = e.allowedEquipment;
        if (raw == null) continue;
        final allowed = (jsonDecode(raw) as List).cast<String>().toSet();
        expect(
          allowed.difference(byMovement[e.movementSlug]!),
          isEmpty,
          reason:
              '${e.name} offers equipment no member of its movement performs',
        );
      }
    });
  });

  group('picker grouping', () {
    Future<List<ExerciseCatalogData>> movementMembers(String slug) {
      return (db.select(db.exerciseCatalog)
            ..where((t) => t.movementSlug.equals(slug)))
          .get();
    }

    test('curl variants collapse into one movement', () async {
      final curls = await movementMembers('curl-isolation');
      final names = curls.map((e) => e.name);

      // Previously "Dumbbell Curl" and "Barbell Bicep Curl" sat in separate
      // families purely because one name said "Bicep" and the other did not.
      expect(
        names,
        containsAll([
          'Barbell Bicep Curl',
          'Dumbbell Curl',
          'EZ Bar Curl',
          'Cable Bicep Curl',
        ]),
      );
    });

    test('incline presses share a movement, flat bench does not', () async {
      final incline = await movementMembers('incline-press-horizontal-push');
      final names = incline.map((e) => e.name);
      expect(
        names,
        containsAll([
          'Incline Barbell Bench',
          'Incline Dumbbell Press',
          'Machine Incline Press',
          'Swiss Bar Incline Press',
        ]),
      );
      expect(names, isNot(contains('Barbell Bench Press')));
    });

    test('the group label does not depend on result ordering', () async {
      final variants = await movementMembers('hip-thrust-hinge');
      expect(variants.length, greaterThan(1));

      final forward = exerciseFamilyLabel(variants);
      final reversed = exerciseFamilyLabel(
        variants.reversed.toList(),
      );
      expect(forward, reversed);
      expect(forward, 'Hip Thrust');
    });
  });

  test('movement slugs all resolve to a real movement', () async {
    final movements =
        (jsonDecode(File('assets/data/movements.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final known = {for (final m in movements) m['slug'] as String};

    final catalog = await db.select(db.exerciseCatalog).get();
    final dangling = catalog
        .map((e) => e.movementSlug)
        .whereType<String>()
        .where((s) => !known.contains(s))
        .toSet();
    expect(dangling, isEmpty);
  });

  test('the canonical member answers to the bare movement name', () async {
    // Searching "curl" or "hip thrust" should reach the group, not whichever
    // qualified variant happens to score highest.
    expect((await bySlug('dumbbell-curl')).aka, contains('Curl'));
    expect((await bySlug('barbell-hip-thrust')).aka, contains('Hip Thrust'));
  });

  test('the canonical member is not an assisted or weighted variant', () async {
    // "Band-Assisted Dip" is a loading choice, not the movement itself.
    final movements =
        (jsonDecode(File('assets/data/movements.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final catalog = await db.select(db.exerciseCatalog).get();
    final nameBySlug = {for (final e in catalog) e.slug: e.name};

    for (final movement in movements) {
      final canonical =
          nameBySlug[movement['canonicalExerciseSlug'] as String]!.toLowerCase();
      final members = catalog
          .where((e) => e.movementSlug == movement['slug'])
          .map((e) => e.name.toLowerCase());
      bool qualifies(String n) =>
          n.contains('assisted') || n.contains('weighted') || n.contains('band');
      // Only enforced where the movement has an unqualified member to pick.
      if (members.any((n) => !qualifies(n))) {
        expect(
          qualifies(canonical),
          isFalse,
          reason: 'movement "${movement['label']}" chose "$canonical"',
        );
      }
    }
  });
}
