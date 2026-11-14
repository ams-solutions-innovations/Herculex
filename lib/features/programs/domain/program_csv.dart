/// CSV codec for program import/export (V2 §12). One header block describing
/// the program, then one row per prescribed exercise:
///
/// ```csv
/// # Herculex Program,name,weeks,periodization
/// program,PPL Block,4,linear
/// week,dayOfWeek,dayName,exercise,sets,repsMin,repsMax,rpe,setType,percent1Rm,equipment
/// 0,1,Push,Bench Press,3,8,12,8,standard,,barbell
/// ```
///
/// Optional advanced columns follow `equipment` (older files without them
/// still decode):
///
/// | column        | meaning                                                  |
/// |---------------|----------------------------------------------------------|
/// | `superset`    | same number on consecutive rows of a day ⇒ one superset |
/// | `restSeconds` | rest after each set of this exercise                     |
/// | `rir`         | reps in reserve (wins over `rpe` when both are present)  |
/// | `role`        | main / supplemental / accessory / isolation / conditioning |
/// | `method`      | straight_sets / double_progression / technique / …       |
/// | `notes`       | free text shown with the exercise (tempo, cues, partials) |
/// | `gear`        | optional add-ons, `|`-separated (see [ProgramGear])     |
/// | `durationSeconds` | time target per set (cardio, planks, holds, carries) |
/// | `distanceM`   | distance target per set in metres (sled, carries, runs)  |
/// | `calories`    | calorie target per set (erg machines)                    |
/// | `setMeta`     | `key=value;key=value` for the set type, e.g. down sets   |
/// | `tempo`       | e.g. `3-1-1-0` (down-pause-up-top), shown in the workout |
/// | `warmup`      | `1` = generate ramp-up warm-up sets before this exercise |
///
/// A down set (`setType=down_sets`, `setMeta=startReps=30;decrement=1`) counts
/// the reps down one set at a time: 30, 29, 28 … 1.
///
/// Pure string ↔ struct codec — DB resolution (exercise names → ids) lives in
/// ProgramCsvIo so this stays unit-testable.
/// Optional add-ons a program row may call for. The user decides at import
/// time (and can change it later) whether to use each one; a gear type that is
/// switched off is simply not prescribed, the exercise stays as written.
abstract final class ProgramGear {
  static const labels = <String, String>{
    'chains': 'Chains',
    'bands': 'Bands',
    'board': 'Board / box',
    'straps': 'Lifting straps',
    'fat_grips': 'Fat grips',
    'belt': 'Lifting belt',
  };

  /// Normalizes a raw cell like `Chains|bands` to known keys, in order.
  static List<String> parse(String? raw) => [
    if (raw != null)
      for (final g in raw.split('|'))
        if (labels.containsKey(g.trim().toLowerCase().replaceAll(' ', '_')))
          g.trim().toLowerCase().replaceAll(' ', '_'),
  ];
}

class ProgramCsvRow {
  final int weekIndex;
  final int dayOfWeek; // 1–7
  final String dayName;
  final String exerciseName;
  final int sets;
  final int? repsMin;
  final int? repsMax;
  final int? rpe;
  final String setType;
  final double? percentOf1Rm;
  final String? equipmentVariant;
  final int? supersetGroup;
  final int? restSeconds;
  final int? rir;
  final String? slotRole;
  final String? trainingMethod;
  final String? notes;

  /// Optional add-ons ([ProgramGear] keys) this row can be done with.
  final List<String> gear;

  /// Per-set time / distance / calorie targets for non-rep exercises.
  final int? durationSeconds;
  final double? distanceM;
  final int? calories;

  /// Set-type parameters, e.g. `{startReps: 30, decrement: 1}` for down sets.
  final Map<String, num> setMeta;
  final String? tempo;
  final bool autoWarmups;

  const ProgramCsvRow({
    required this.weekIndex,
    required this.dayOfWeek,
    required this.dayName,
    required this.exerciseName,
    required this.sets,
    this.repsMin,
    this.repsMax,
    this.rpe,
    this.setType = 'standard',
    this.percentOf1Rm,
    this.equipmentVariant,
    this.supersetGroup,
    this.restSeconds,
    this.rir,
    this.slotRole,
    this.trainingMethod,
    this.notes,
    this.gear = const [],
    this.durationSeconds,
    this.distanceM,
    this.calories,
    this.setMeta = const {},
    this.tempo,
    this.autoWarmups = false,
  });
}

class ProgramCsvDocument {
  final String name;
  final int weeks;
  final String periodizationModel;
  final List<ProgramCsvRow> rows;

  const ProgramCsvDocument({
    required this.name,
    required this.weeks,
    required this.periodizationModel,
    required this.rows,
  });
}

class ProgramCsvFormatException implements Exception {
  final String message;
  const ProgramCsvFormatException(this.message);
  @override
  String toString() => 'ProgramCsvFormatException: $message';
}

class ProgramCsv {
  static const _exerciseHeader =
      'week,dayOfWeek,dayName,exercise,sets,repsMin,repsMax,rpe,setType,percent1Rm,equipment,'
      'superset,restSeconds,rir,role,method,notes,gear,'
      'durationSeconds,distanceM,calories,setMeta,tempo,warmup';

  static String encode(ProgramCsvDocument doc) {
    final b = StringBuffer()
      ..writeln('# Herculex Program,name,weeks,periodization')
      ..writeln(
        'program,${_escape(doc.name)},${doc.weeks},${doc.periodizationModel}',
      )
      ..writeln(_exerciseHeader);
    for (final r in doc.rows) {
      b.writeln(
        [
          r.weekIndex,
          r.dayOfWeek,
          _escape(r.dayName),
          _escape(r.exerciseName),
          r.sets,
          r.repsMin ?? '',
          r.repsMax ?? '',
          r.rpe ?? '',
          r.setType,
          r.percentOf1Rm ?? '',
          r.equipmentVariant ?? '',
          r.supersetGroup ?? '',
          r.restSeconds ?? '',
          r.rir ?? '',
          r.slotRole ?? '',
          r.trainingMethod ?? '',
          _escape(r.notes ?? ''),
          r.gear.join('|'),
          r.durationSeconds ?? '',
          r.distanceM ?? '',
          r.calories ?? '',
          _escape(
            r.setMeta.entries.map((e) => '${e.key}=${e.value}').join(';'),
          ),
          r.tempo ?? '',
          r.autoWarmups ? 1 : '',
        ].join(','),
      );
    }
    return b.toString();
  }

  static ProgramCsvDocument decode(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();
    if (lines.isEmpty) {
      throw const ProgramCsvFormatException('Empty file');
    }

    final programLine = _split(lines.first);
    if (programLine.length < 4 || programLine[0] != 'program') {
      throw const ProgramCsvFormatException(
        'First data row must be: program,<name>,<weeks>,<periodization>',
      );
    }
    final name = programLine[1];
    final weeks = int.tryParse(programLine[2]);
    if (name.isEmpty || weeks == null || weeks < 1) {
      throw const ProgramCsvFormatException('Invalid program name or weeks');
    }

    final rows = <ProgramCsvRow>[];
    for (final line in lines.skip(1)) {
      final cells = _split(line);
      if (cells.first == 'week') continue; // column header row
      if (cells.length < 5) {
        throw ProgramCsvFormatException('Malformed row: $line');
      }
      final week = int.tryParse(cells[0]);
      final dayOfWeek = int.tryParse(cells[1]);
      final sets = int.tryParse(cells[4]);
      if (week == null || dayOfWeek == null || sets == null) {
        throw ProgramCsvFormatException('Malformed row: $line');
      }
      if (dayOfWeek < 1 || dayOfWeek > 7) {
        throw ProgramCsvFormatException('dayOfWeek must be 1–7 in: $line');
      }
      String? cell(int i) =>
          i < cells.length && cells[i].isNotEmpty ? cells[i] : null;
      rows.add(
        ProgramCsvRow(
          weekIndex: week,
          dayOfWeek: dayOfWeek,
          dayName: cells[2],
          exerciseName: cells[3],
          sets: sets,
          repsMin: int.tryParse(cell(5) ?? ''),
          repsMax: int.tryParse(cell(6) ?? ''),
          rpe: int.tryParse(cell(7) ?? ''),
          setType: cell(8) ?? 'standard',
          percentOf1Rm: double.tryParse(cell(9) ?? ''),
          equipmentVariant: cell(10),
          supersetGroup: int.tryParse(cell(11) ?? ''),
          restSeconds: int.tryParse(cell(12) ?? ''),
          rir: int.tryParse(cell(13) ?? ''),
          slotRole: cell(14),
          trainingMethod: cell(15),
          notes: cell(16),
          gear: ProgramGear.parse(cell(17)),
          durationSeconds: int.tryParse(cell(18) ?? ''),
          distanceM: double.tryParse(cell(19) ?? ''),
          calories: int.tryParse(cell(20) ?? ''),
          setMeta: _parseSetMeta(cell(21)),
          tempo: cell(22),
          autoWarmups: const {
            '1',
            'true',
            'yes',
          }.contains(cell(23)?.toLowerCase()),
        ),
      );
    }

    for (final r in rows) {
      if (r.setType == 'down_sets' && !((r.setMeta['startReps'] ?? 0) > 0)) {
        throw ProgramCsvFormatException(
          'down_sets needs setMeta=startReps=N (and optional decrement=N): '
          '${r.exerciseName}',
        );
      }
    }

    return ProgramCsvDocument(
      name: name,
      weeks: weeks,
      periodizationModel: programLine.length > 3 && programLine[3].isNotEmpty
          ? programLine[3]
          : 'none',
      rows: rows,
    );
  }

  static Map<String, num> _parseSetMeta(String? raw) {
    if (raw == null) return const {};
    final out = <String, num>{};
    for (final part in raw.split(';')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final v = num.tryParse(kv[1].trim());
      if (v != null) out[kv[0].trim()] = v;
    }
    return out;
  }

  /// Minimal CSV quoting: fields containing commas or quotes get quoted.
  static String _escape(String s) =>
      s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;

  /// Splits one CSV line honoring double-quoted fields.
  static List<String> _split(String line) {
    final cells = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          current.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        cells.add(current.toString());
        current.clear();
      } else {
        current.write(c);
      }
    }
    cells.add(current.toString());
    return cells;
  }
}
