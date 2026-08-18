// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';

void main() {
  final logFile = File(r'C:\Users\marti\.gemini\antigravity\brain\9aa902b5-f41f-4922-8532-67f2e72c8e1a\.system_generated\tasks\task-126.log');
  final lines = logFile.readAsLinesSync();

  final Map<String, Set<int>> filesToFix = {};

  for (final line in lines) {
    if (line.contains('invalid_constant') || line.contains('const_initialized_with_non_constant_value') || line.contains('const_with_non_constant_argument') || line.contains('prefer_const_constructors_in_immutables') || line.contains('non_constant_default_value')) {
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
        final idx = lineNum - 1;
        // Search upwards up to 5 lines for a const
        for (int j = idx; j >= 0 && j >= idx - 5; j--) {
          if (content[j].contains('const ')) {
            content[j] = content[j].replaceAll(RegExp(r'\bconst\s+'), '');
            break;
          }
        }
      }
    }
    file.writeAsStringSync(content.join('\n'), encoding: utf8);
    print('Fixed ${entry.key}');
  }
}
