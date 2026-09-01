// Structure guard for lib/. Run it wherever you run `flutter analyze`:
//
//     dart run tool/check_structure.dart
//
// The analyzer enforces language rules; this enforces the layout rules that
// the September 2026 restructure established, because a convention nobody
// checks decays back into a flat folder within a few months. Every rule below
// exists because the codebase actually had the problem.
//
// Exit code 0 = clean, 1 = violations (printed, grouped by rule).
import 'dart:io';

/// Hand-written files may not exceed this. Generated files are exempt.
///
/// The point is AI- and human-editability: a 2,700-line widget file cannot be
/// read in one pass, and every edit to it risks landing in the wrong one of
/// its twenty-odd private sub-widgets.
const int kMaxLines = 600;

/// Files that are over [kMaxLines] and knowingly not split yet.
///
/// This list is a to-do, not a permission slip — Wave 4 of the restructure is
/// working through it. Add to it only with a reason; the goal is an empty map.
const Map<String, String> kLineCountExemptions = {
  // Owned by UI-rework Phase 7, which is blocked on GSD Phase 10 landing and
  // has "split active_exercise_card.dart" as an explicit deliverable. Splitting
  // it here would hand that phase a merge conflict.
  'lib/features/workouts/presentation/widgets/active_exercise_card.dart':
      'UI-rework P7 owns this split',

  // Drift table declarations. Splittable by domain, but only if
  // `build_runner` still emits a byte-identical database.g.dart — until that
  // is verified, leave it whole.
  'lib/data/local/tables.dart': 'drift codegen must stay byte-identical',
};

/// Generated or vendored files nothing in here applies to.
bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.drift.dart');

/// Directories that must not depend on features/.
///
/// The dependency runs one way — features build on core and the design
/// system, never the reverse. A design-system widget that reaches into a
/// feature cannot be reused by any other feature, which defeats the point of
/// having it.
const List<String> kFeatureFreeRoots = ['lib/core/', 'lib/design_system/'];

/// Features exempt from the presentation/ layout rules.
///
/// lib/features/reps/ belongs to the in-flight GSD Phase 10 and was
/// deliberately left out of the restructure. Remove this once that lands.
const Set<String> kLayoutExemptFeatures = {'reps'};

/// Below this many files, a flat presentation/ folder is easier to scan than
/// four subfolders holding one file each.
const int kPresentationSplitThreshold = 8;

class Violation {
  Violation(this.rule, this.path, this.detail);
  final String rule;
  final String path;
  final String detail;
}

void main() {
  final violations = <Violation>[];
  final dartFiles =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.dart'))
          .toList()
        ..sort();

  for (final path in dartFiles) {
    if (_isGenerated(path)) continue;
    final lines = File(path).readAsLinesSync();
    // Only real directives count. Matching raw file text instead would flag
    // any doc comment that *names* a forbidden path — including the one in
    // design_system.dart that states this very rule.
    final directives = lines
        .map((l) => l.trimLeft())
        .where((l) => l.startsWith('import ') || l.startsWith('export '))
        .toList();

    // ---- Rule 1: file length -------------------------------------------
    if (lines.length > kMaxLines && !kLineCountExemptions.containsKey(path)) {
      violations.add(
        Violation('file over $kMaxLines lines', path, '${lines.length} lines'),
      );
    }

    // ---- Rule 2: layering ----------------------------------------------
    for (final root in kFeatureFreeRoots) {
      if (!path.startsWith(root)) continue;
      final offenders = directives
          .where((d) => d.contains('package:herculex/features/'))
          .map(_directiveTarget)
          .toList();
      if (offenders.isNotEmpty) {
        violations.add(
          Violation(
            '$root must not import features/',
            path,
            offenders.join(', '),
          ),
        );
      }
    }

    // ---- Rule 3: file kind matches folder ------------------------------
    final feature = _featureOf(path);
    if (feature != null && !kLayoutExemptFeatures.contains(feature)) {
      violations.addAll(_checkPlacement(path));
    }
  }

  // ---- Rule 4: presentation/ split past the threshold --------------------
  for (final dir in Directory(
    'lib/features',
  ).listSync().whereType<Directory>()) {
    final feature = dir.path.replaceAll(r'\', '/').split('/').last;
    if (kLayoutExemptFeatures.contains(feature)) continue;
    final presentation = Directory('lib/features/$feature/presentation');
    if (!presentation.existsSync()) continue;
    final flat = presentation
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .length;
    if (flat >= kPresentationSplitThreshold) {
      violations.add(
        Violation(
          'presentation/ needs views/sheets/dialogs/widgets',
          'lib/features/$feature/presentation',
          '$flat files at the top level (threshold '
              '$kPresentationSplitThreshold)',
        ),
      );
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('lib/ structure OK (${dartFiles.length} files checked)');
    exit(0);
  }

  final byRule = <String, List<Violation>>{};
  for (final v in violations) {
    byRule.putIfAbsent(v.rule, () => []).add(v);
  }
  for (final entry in byRule.entries) {
    stdout.writeln('\n${entry.key} (${entry.value.length}):');
    for (final v in entry.value) {
      stdout.writeln('  ${v.path} — ${v.detail}');
    }
  }
  stdout.writeln(
    '\n${violations.length} violation(s). See docs/ARCHITECTURE.md for the '
    'rules, or tool/check_structure.dart to amend them deliberately.',
  );
  exit(1);
}

/// `import 'package:herculex/features/x/y.dart';` -> `features/x/y.dart`,
/// so the report names the offending dependency rather than the whole line.
String _directiveTarget(String directive) {
  final match = RegExp("package:herculex/([^']+)").firstMatch(directive);
  return match?.group(1) ?? directive.trim();
}

String? _featureOf(String path) {
  final parts = path.split('/');
  if (parts.length < 3 || parts[1] != 'features') return null;
  return parts[2];
}

/// A `*_view.dart` in a split feature belongs in `presentation/views/`, and so
/// on. Only checked for features that have actually been split — everything
/// else keeps a flat presentation/ by design.
List<Violation> _checkPlacement(String path) {
  final out = <Violation>[];
  final name = path.split('/').last;
  final feature = _featureOf(path)!;
  final isSplit = Directory(
    'lib/features/$feature/presentation/views',
  ).existsSync();
  if (!isSplit || !path.contains('/presentation/')) {
    // Providers belong in application/ regardless of whether the feature's
    // presentation/ has been split — that rule is universal.
    if (path.contains('/presentation/') && _looksLikeProvider(name)) {
      out.add(
        Violation(
          'providers belong in application/',
          path,
          'move to lib/features/$feature/application/',
        ),
      );
    }
    return out;
  }

  const expected = {
    '_view.dart': 'views',
    '_sheet.dart': 'sheets',
    '_dialog.dart': 'dialogs',
  };
  for (final entry in expected.entries) {
    if (name.endsWith(entry.key) &&
        !path.contains('/presentation/${entry.value}/')) {
      out.add(
        Violation(
          '*${entry.key} belongs in presentation/${entry.value}/',
          path,
          'currently outside ${entry.value}/',
        ),
      );
    }
  }
  if (_looksLikeProvider(name)) {
    out.add(
      Violation(
        'providers belong in application/',
        path,
        'move to lib/features/$feature/application/',
      ),
    );
  }
  return out;
}

bool _looksLikeProvider(String name) =>
    name.endsWith('_providers.dart') ||
    name.endsWith('_provider.dart') ||
    name.endsWith('_controller.dart');
