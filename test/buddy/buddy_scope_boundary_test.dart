import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BUD-03's enforcement as a static source test over the buddy transport
/// module: every `.dart` file under `lib/features/buddy/data/`, plus the
/// single file `lib/features/buddy/domain/buddy_event.dart`.
///
/// The rule: the caller-side broadcast-vs-local-only decision (the enum in
/// `buddy_scope.dart`, deliberately not part of this module) must never
/// reach the wire. A change in who an action is visible to simply never
/// gets to the publisher, let alone the wire — see `11-RESEARCH.md`
/// § Pitfall 5.
///
/// Four independent checks, all with `//`-comment lines stripped first (same
/// helper as the Phase 10 precedent,
/// `test/rep_tracker_write_boundary_test.dart`):
///
///  1. Non-vacuity: the file list is non-empty and includes
///     `buddy_event_publisher.dart`.
///  2. No file contains the identifier `BuddyScope`.
///  3. No file contains the literal `'mine'` or `"mine"`.
///  4. No file contains an `import` whose path ends in `buddy_scope.dart`.
void main() {
  late List<File> transportFiles;

  setUpAll(() {
    final dataDir = Directory('lib/features/buddy/data');
    final eventFile = File('lib/features/buddy/domain/buddy_event.dart');

    expect(
      dataDir.existsSync(),
      isTrue,
      reason:
          'Expected lib/features/buddy/data/ to exist — run from repo root.',
    );
    expect(
      eventFile.existsSync(),
      isTrue,
      reason:
          'Expected lib/features/buddy/domain/buddy_event.dart to exist — '
          'run from repo root.',
    );

    transportFiles =
        [
            ...dataDir
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')),
            eventFile,
          ]
          ..sort((a, b) => a.path.compareTo(b.path));

    // Non-vacuity guard (check 1): the set must be non-empty and must
    // actually include the publisher seam, or this gate could pass on an
    // empty or accidentally-narrowed file list.
    expect(transportFiles, isNotEmpty);
    expect(
      transportFiles.any(
        (f) => f.path.endsWith('buddy_event_publisher.dart'),
      ),
      isTrue,
      reason:
          'Expected the buddy transport module to include '
          'buddy_event_publisher.dart — a file list missing it would let '
          'this gate pass vacuously.',
    );
  });

  /// Strips `//`-prefixed line comments (after trimming leading whitespace)
  /// so a doc comment explaining the rule cannot itself trigger a match.
  List<String> codeLines(String content) {
    return [
      for (final rawLine in content.split('\n'))
        if (!rawLine.trim().startsWith('//')) rawLine,
    ];
  }

  const failureReason =
      'BUD-03: the broadcast-vs-local-only decision is control flow in the '
      'caller, never a field on the wire; a "mine" change must never reach '
      'the publisher. Violations:\n';

  test('no file in the buddy transport module references BuddyScope', () {
    final violations = <String>[];
    for (final file in transportFiles) {
      final lines = codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('BuddyScope')) {
          violations.add('${file.path}:${i + 1}: contains "BuddyScope"');
        }
      }
    }
    expect(violations, isEmpty, reason: '$failureReason${violations.join('\n')}');
  });

  test(
    'no file in the buddy transport module contains a "mine" string literal',
    () {
      final violations = <String>[];
      for (final file in transportFiles) {
        final lines = codeLines(file.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains("'mine'") || lines[i].contains('"mine"')) {
            violations.add(
              '${file.path}:${i + 1}: contains a "mine" string literal',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '$failureReason${violations.join('\n')}',
      );
    },
  );

  test(
    'no file in the buddy transport module imports buddy_scope.dart',
    () {
      final violations = <String>[];
      for (final file in transportFiles) {
        final lines = codeLines(file.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final isImport = line.trim().startsWith('import ');
          if (isImport && line.trim().endsWith("buddy_scope.dart';")) {
            violations.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '$failureReason${violations.join('\n')}',
      );
    },
  );
}
