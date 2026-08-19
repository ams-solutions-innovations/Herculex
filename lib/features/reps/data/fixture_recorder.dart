import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/motion_sample.dart';
import '../domain/rep_movement.dart';

/// On-device CSV+sidecar reader/writer for the REP-06 fixture corpus,
/// matching `10-02-PLAN.md`'s fixture format byte-for-byte:
///
///  * `<name>.csv` — a `t_ms,x,y,z` body (see [MotionTrace.toCsv]).
///  * `<name>.json` — the ten-key provenance sidecar from 10-02's
///    `<interfaces>` block, with **`synthetic: false` hardcoded** — this
///    recorder can never produce a fixture that fails
///    `test/rep_fixture_provenance_test.dart`'s provenance gate on that key.
///
/// Writes to app-private documents storage only (not shared/external
/// storage) — see 10-06's threat register, T-10-18. Files here are not yet
/// part of the repo's `test/fixtures/motion/` corpus; the developer exports
/// and commits them by hand.
class FixtureRecorder {
  FixtureRecorder({Directory Function()? baseDirOverride})
      : _baseDirOverride = baseDirOverride;

  /// Test seam: when non-null, used instead of
  /// `getApplicationDocumentsDirectory()` so tests can point this at a temp
  /// directory without touching the real app documents dir.
  final Directory Function()? _baseDirOverride;

  Future<Directory> fixturesDir() async {
    final override = _baseDirOverride;
    final base = override != null
        ? override()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/fixtures/motion');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes `<name>.csv` and `<name>.json` for [trace] under [fixturesDir].
  ///
  /// `synthetic: false` is a literal in the written JSON, never a parameter
  /// — see the class doc and 10-06's threat register T-10-19.
  Future<void> save(
    String name,
    MotionTrace trace, {
    required int repCount,
    required RepMovement? movement,
    required String source,
    String? placement,
    required String description,
    required String recordedBy,
    required String deviceModel,
  }) async {
    final dir = await fixturesDir();

    final csvFile = File('${dir.path}/$name.csv');
    await csvFile.writeAsString(trace.toCsv());

    final sidecar = <String, dynamic>{
      'repCount': repCount,
      // The stable family id, never `.name`: the enum may be reordered or
      // renamed and a sidecar recorded today must still resolve later.
      'movement': movement?.id,
      'source': source,
      'placement': placement,
      'sensorType': trace.sensorType,
      'description': description,
      'recordedBy': recordedBy,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceModel': deviceModel,
      'synthetic': false,
    };

    final jsonFile = File('${dir.path}/$name.json');
    await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(sidecar));
  }

  /// Base names with **both** a `.csv` and a `.json` present under
  /// [fixturesDir]. A lone half-written pair (e.g. from an interrupted save)
  /// does not count as recorded.
  Future<List<String>> listRecorded() async {
    final dir = await fixturesDir();
    if (!await dir.exists()) return const [];

    final csvNames = <String>{};
    final jsonNames = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      final fileName = path.split('/').last;
      if (fileName.endsWith('.csv')) {
        csvNames.add(fileName.substring(0, fileName.length - 4));
      } else if (fileName.endsWith('.json')) {
        jsonNames.add(fileName.substring(0, fileName.length - 5));
      }
    }
    return csvNames.intersection(jsonNames).toList()..sort();
  }

  /// Every `.csv`/`.json` file under [fixturesDir], for the export action.
  Future<List<File>> allFixtureFiles() async {
    final dir = await fixturesDir();
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          (entity.path.endsWith('.csv') || entity.path.endsWith('.json'))) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }
}
