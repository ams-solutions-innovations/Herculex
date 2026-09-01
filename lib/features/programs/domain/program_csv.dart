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
/// Pure string ↔ struct codec — DB resolution (exercise names → ids) lives in
/// ProgramCsvIo so this stays unit-testable.
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
      'week,dayOfWeek,dayName,exercise,sets,repsMin,repsMax,rpe,setType,percent1Rm,equipment';

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
        ),
      );
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
