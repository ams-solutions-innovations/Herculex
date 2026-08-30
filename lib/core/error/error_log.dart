import 'dart:collection';

import 'package:flutter/foundation.dart';

/// One captured error, with just enough context to identify it later.
@immutable
class AppErrorRecord {
  const AppErrorRecord({
    required this.time,
    required this.summary,
    required this.source,
    this.details,
    this.stack,
  });

  final DateTime time;

  /// First line of the exception — what's shown in the collapsed list.
  final String summary;

  /// Where the error came from: `widget`, `flutter`, `platform`, `zone`,
  /// `router`. Used to tell a build failure from a dropped Future.
  final String source;

  /// Library/context string from `FlutterErrorDetails`, when there was one.
  final String? details;

  final String? stack;
}

/// In-memory ring buffer of the most recent errors.
///
/// The app ships no crash reporter (see `Env.sentryDsn`, declared but unused),
/// so before this existed an uncaught error in release left no trace at all —
/// `ErrorWidget`'s release build is a blank grey box and the root zone's
/// handler only prints. This keeps the last [capacity] errors addressable from
/// the admin dashboard so a user can read back what actually failed.
///
/// Deliberately memory-only: no file I/O, no dependency, nothing that could
/// itself throw while handling an error.
class ErrorLog {
  ErrorLog._();

  static final ErrorLog instance = ErrorLog._();

  static const int capacity = 50;

  final Queue<AppErrorRecord> _records = Queue<AppErrorRecord>();

  /// Bumps on every record so a listening widget can rebuild without the
  /// log taking a dependency on Riverpod.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Newest first.
  List<AppErrorRecord> get records => _records.toList(growable: false).reversed
      .toList(growable: false);

  int get length => _records.length;

  void record(
    Object error, {
    required String source,
    StackTrace? stack,
    String? details,
  }) {
    // Never let the error path throw: a bad toString() must not escalate a
    // handled error into an unhandled one.
    String summary;
    try {
      summary = error.toString();
    } catch (_) {
      summary = '<error object threw on toString()>';
    }
    final firstLine = summary.split('\n').first.trim();

    _records.addLast(
      AppErrorRecord(
        time: DateTime.now(),
        summary: firstLine.isEmpty ? summary : firstLine,
        source: source,
        details: details,
        stack: stack?.toString(),
      ),
    );
    while (_records.length > capacity) {
      _records.removeFirst();
    }
    revision.value++;
  }

  void clear() {
    _records.clear();
    revision.value++;
  }
}
