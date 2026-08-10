import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/preset_program.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';

/// Guards the marketplace preset catalog: every program listed in
/// assets/programs/catalog.json must decode cleanly and every exercise name
/// it references must resolve against the shipped exercise catalog — exactly
/// what ProgramCsvIo.importProgram checks at import time, run here so a bad
/// preset never reaches a user as a runtime "Unknown exercises" error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PresetProgramMeta> catalog;
  late Set<String> knownExerciseNames;

  setUpAll(() {
    final catalogRaw = File('assets/programs/catalog.json').readAsStringSync();
    final catalogJson = jsonDecode(catalogRaw) as Map<String, dynamic>;
    catalog = (catalogJson['programs'] as List)
        .map((e) => PresetProgramMeta.fromJson(e as Map<String, dynamic>))
        .toList();

    final exercisesRaw = File('assets/data/exercises.json').readAsStringSync();
    final exercises = (jsonDecode(exercisesRaw) as List).cast<Map<String, dynamic>>();
    knownExerciseNames = {
      for (final e in exercises) (e['name'] as String).toLowerCase(),
      for (final e in exercises)
        for (final aka in (e['aka'] as List? ?? const []))
          (aka as String).toLowerCase(),
    };
  });

  test('catalog has at least one preset', () {
    expect(catalog, isNotEmpty);
  });

  test('every preset decodes and matches its manifest week count', () {
    for (final meta in catalog) {
      final csv = File(meta.file).readAsStringSync();
      final doc = ProgramCsv.decode(csv);
      expect(doc.weeks, meta.weeks, reason: '${meta.id}: weeks mismatch between catalog.json and CSV');
    }
  });

  test('every preset exercise resolves against the catalog', () {
    final failures = <String>[];
    for (final meta in catalog) {
      final csv = File(meta.file).readAsStringSync();
      final doc = ProgramCsv.decode(csv);
      for (final row in doc.rows) {
        if (!knownExerciseNames.contains(row.exerciseName.toLowerCase())) {
          failures.add('${meta.id}: "${row.exerciseName}"');
        }
      }
    }
    expect(failures, isEmpty, reason: 'Unknown exercises: ${failures.join(', ')}');
  });

  test('every preset level and goal use documented values', () {
    const levels = {'beginner', 'intermediate', 'advanced'};
    const goals = {'strength', 'hypertrophy', 'general'};
    for (final meta in catalog) {
      expect(levels.contains(meta.level), isTrue, reason: '${meta.id}: unexpected level "${meta.level}"');
      expect(goals.contains(meta.goal), isTrue, reason: '${meta.id}: unexpected goal "${meta.goal}"');
    }
  });
}
