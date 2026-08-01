import 'dart:io';
import 'dart:convert';

void main() {
  final logFile = File(r'C:\Users\marti\.gemini\antigravity\brain\9aa902b5-f41f-4922-8532-67f2e72c8e1a\.system_generated\tasks\task-107.log');
  final lines = logFile.readAsLinesSync();

  final Map<String, Set<int>> filesToFix = {};

  for (final line in lines) {
    if (line.contains('invalid_constant') || line.contains('const_initialized_with_non_constant_value') || line.contains('const_with_non_constant_argument')) {
      final parts = line.split(' - ');
      if (parts.length >= 3) {
        final loc = parts[2].trim();
        final match = RegExp(r'(lib\\[^:]+):(\d+):').firstMatch(loc);
        if (match != null) {
          final file = match.group(1)!;
          final lineNum = int.parse(match.group(2)!);
          filesToFix.putIfAbsent(file, () => {}).add(lineNum);
        }
      }
    }
  }

  for (final entry in filesToFix.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) continue;

    final content = file.readAsLinesSync(encoding: utf8);
    for (final lineNum in entry.value) {
      if (lineNum <= content.length) {
        // Line number is 1-based
        final idx = lineNum - 1;
        content[idx] = content[idx].replaceAll(RegExp(r'\bconst\s+'), '');
      }
    }
    file.writeAsStringSync(content.join('\n'), encoding: utf8);
    print('Fixed ${entry.key}');
  }
}
