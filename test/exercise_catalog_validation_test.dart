import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/test_database.dart';

/// Invariants over the shipped catalog asset.
///
/// These guard the identity scheme the importer and merge engine depend on.
/// A duplicate or missing slug would silently reintroduce the bug slugs exist
/// to fix: the importer falling back to name matching and inserting a second
/// row instead of updating in place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> rows;

  setUpAll(() {
    final raw = File('assets/data/exercises.json').readAsStringSync();
    rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  });

  test('every exercise carries a non-empty slug', () {
    final missing = [
      for (final row in rows)
        if ((row['slug'] as String?)?.trim().isEmpty ?? true) row['name'],
    ];
    expect(missing, isEmpty, reason: 'exercises without a slug: $missing');
  });

  test('slugs are unique', () {
    final seen = <String, String>{};
    final collisions = <String>[];
    for (final row in rows) {
      final slug = row['slug'] as String;
      final previous = seen[slug];
      if (previous != null) {
        collisions.add('$slug: "$previous" vs "${row['name']}"');
      }
      seen[slug] = row['name'] as String;
    }
    expect(collisions, isEmpty);
  });

  test('slugs are kebab-case', () {
    final malformed = [
      for (final row in rows)
        if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(row['slug'] as String))
          row['slug'],
    ];
    expect(malformed, isEmpty);
  });

  test('each equipment value maps to exactly one modality', () {
    // equipment is a display-level refinement of modality, not a parallel
    // axis. If one equipment value ever resolves to two modalities, plate
    // rounding in progression_engine and the machine checks in the active
    // workout card start disagreeing with the picker.
    final byEquipment = <String, Set<String>>{};
    for (final row in rows) {
      byEquipment
          .putIfAbsent(row['equipment'] as String, () => <String>{})
          .add(row['modality'] as String);
    }
    final ambiguous = {
      for (final entry in byEquipment.entries)
        // "Machine" legitimately splits plate-loaded vs selectorized.
        if (entry.value.length > 1 && entry.key != 'Machine')
          entry.key: entry.value,
    };
    expect(ambiguous, isEmpty);
  });

  test('modality values are drawn from the known set', () {
    const known = {
      'barbell',
      'dumbbell',
      'machine_plate',
      'machine_selectorized',
      'cable',
      'smith',
      'kettlebell',
      'band',
      'bodyweight',
      'other',
    };
    final unknown = rows
        .map((r) => r['modality'] as String)
        .where((m) => !known.contains(m))
        .toSet();
    expect(unknown, isEmpty);
  });

  test('the importer lands every slug in the database, uniquely', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final catalog = await db.select(db.exerciseCatalog).get();
    expect(catalog.length, greaterThanOrEqualTo(rows.length));

    final slugs = catalog.map((e) => e.slug).whereType<String>().toList();
    expect(
      slugs.length,
      rows.length,
      reason: 'every seeded row should have imported its slug',
    );
    expect(slugs.toSet().length, slugs.length, reason: 'slugs must be unique');
  });
}
