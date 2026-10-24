import 'package:flutter/material.dart';

/// A manual edit always has an explicit, inclusive local start day.
Future<DateTime?> chooseTargetStartDate(
  BuildContext context, {
  required DateTime now,
}) async {
  final today = DateTime(now.year, now.month, now.day);
  final choice = await showDialog<int>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('When should these goals start?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, 0),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('From today'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, 1),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('From tomorrow'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, 2),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Custom date'),
          ),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) {
    return null;
  }
  if (choice == 0) {
    return today;
  }
  if (choice == 1) {
    return DateTime(today.year, today.month, today.day + 1);
  }
  return showDatePicker(
    context: context,
    initialDate: today,
    firstDate: DateTime(1),
    lastDate: DateTime(9999, 12, 31),
    helpText: 'Goals apply from this date onwards',
  );
}
