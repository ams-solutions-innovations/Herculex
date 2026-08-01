import 'dart:io';
import 'dart:convert';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    try {
      String content = file.readAsStringSync(encoding: utf8);
      bool changed = false;

      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('AppColors.') && lines[i].contains('const ')) {
          lines[i] = lines[i].replaceAll(RegExp(r'\bconst\s+'), '');
          changed = true;
        }
      }

      if (changed) {
        file.writeAsStringSync(lines.join('\n'), encoding: utf8);
        print('Updated ${file.path}');
      }
    } catch (e) {
      print('Skipped ${file.path}: $e');
    }
  }
}
