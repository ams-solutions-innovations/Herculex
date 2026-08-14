import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REP-03's enforcement as a static source test over the whole of
/// `lib/features/reps/` — the tracker's non-negotiable: "nothing under
/// `lib/features/reps/` may reach the set write path; the tracker's terminal
/// output is an immutable `RepSuggestion`, and the review sheet writes only
/// through the `onConfirm` callback injected by `active_workout_view.dart`"
/// (originally `active_exercise_card.dart` in this codebase's actual
/// layout — see the plan-vs-code deviation recorded in the 10-04 summary;
/// the rule itself is unaffected by which workouts file owns the callback).
///
/// Two independent checks, both over every `.dart` file under
/// `lib/features/reps/`:
///
///  1. No file contains `WorkoutsRepository`, `updateSet`,
///     `SetEntriesCompanion` or a raw `db.setEntries` table reference (the
///     latter stands in for the plan's literal `db.update(` token — scoped
///     to the actual set-entries table rather than to drift's generic
///     `.update(` method, which `rep_tracking_repository.dart` legitimately
///     calls against its own local-only tables).
///  2. No file imports anything whose path contains `features/workouts/` —
///     matched across the *whole* feature directory (not just `data/`), so a
///     `presentation/` import — which would give the tracker a transitive
///     route to the write path through a view that itself holds the
///     repository — is caught too.
///
/// Line comments are stripped before matching, so a comment documenting the
/// rule (like this file's own header, or the doc comments inside the
/// tracker files) can never itself trip the test.
void main() {
  late Directory repsDir;
  late List<File> dartFiles;

  setUpAll(() {
    repsDir = Directory('lib/features/reps');
    expect(
      repsDir.existsSync(),
      isTrue,
      reason: 'Expected lib/features/reps/ to exist — run from repo root.',
    );
    dartFiles = repsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(dartFiles, isNotEmpty);
  });

  /// Strips `//`-prefixed line comments (after trimming leading whitespace)
  /// so a doc comment explaining the rule cannot itself trigger a match.
  /// Deliberately conservative: a line whose *code* also happens to contain
  /// `//` (a URL, say) is not attempted here — none of the forbidden tokens
  /// below could plausibly appear inside one.
  List<String> codeLines(String content) {
    return [
      for (final rawLine in content.split('\n'))
        if (!rawLine.trim().startsWith('//')) rawLine,
    ];
  }

  const forbiddenSymbols = [
    'WorkoutsRepository',
    'updateSet',
    'SetEntriesCompanion',
    'db.setEntries',
  ];

  test('no file under lib/features/reps/ references the set write path', () {
    final violations = <String>[];
    for (final file in dartFiles) {
      final lines = codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        for (final symbol in forbiddenSymbols) {
          if (lines[i].contains(symbol)) {
            violations.add('${file.path}:${i + 1}: contains "$symbol"');
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'nothing under lib/features/reps/ may reach the set write path; '
          "the tracker's terminal output is an immutable RepSuggestion, and "
          'the review sheet writes only through the onConfirm callback '
          'injected by the workouts feature. Violations:\n'
          '${violations.join('\n')}',
    );
  });

  test(
    'no file under lib/features/reps/ imports anything from '
    'lib/features/workouts/ (presentation/ included)',
    () {
      // Every file under lib/features/reps/ uses relative imports (matching
      // the rest of the codebase's convention), so a workouts import reads
      // as `'../../workouts/presentation/....dart'`, not the
      // `package:herculex/features/workouts/...` form the plan's literal
      // `features/workouts/` substring assumes. `/workouts/` (a path
      // segment, not a bare word) matches both that relative form and a
      // hypothetical `package:` import, while still requiring a real path
      // boundary on each side so it cannot match on, say, a variable named
      // `workoutsRepository`.
      final workoutsSegment = RegExp(r'(^|[/'
          "'"
          r'])workouts/');
      final violations = <String>[];
      for (final file in dartFiles) {
        final lines = codeLines(file.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final isImportOrExport =
              line.trim().startsWith('import ') || line.trim().startsWith('export ');
          if (isImportOrExport && workoutsSegment.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'nothing under lib/features/reps/ may reach the set write path; '
            "the tracker's terminal output is an immutable RepSuggestion, and "
            'the review sheet writes only through the onConfirm callback '
            'injected by the workouts feature — a presentation/ import would '
            'give the tracker a transitive route to WorkoutsRepository '
            'through a view that itself holds it. Violations:\n'
            '${violations.join('\n')}',
      );
    },
  );
}
