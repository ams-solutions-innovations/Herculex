import 'dart:async';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';

/// Local-only receipts. The receipt and the affected rows share the SQLite
/// transaction, including a crash between the database commit and the WC ack.
class WatchCommandInbox {
  WatchCommandInbox(this.db);
  final AppDatabase db;

  static Future<void> createTables(AppDatabase db) async {
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS processed_watch_commands (
  kind TEXT NOT NULL, command_id TEXT NOT NULL, applied_at INTEGER NOT NULL,
  PRIMARY KEY (kind, command_id)
)''');
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS apple_watch_sessions (
  entity_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, terminal INTEGER NOT NULL DEFAULT 0,
  payload_json TEXT NOT NULL, session_id INTEGER
)''');
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS watch_health_exports (
  entity_id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL,
  healthkit_uuid TEXT
)''');
  }

  Future<bool> wasApplied(String kind, String id) async =>
      (await db
              .customSelect(
                'SELECT 1 FROM processed_watch_commands WHERE kind = ? AND command_id = ?',
                variables: [Variable(kind), Variable(id)],
              )
              .get())
          .isNotEmpty;

  Future<bool> applyOnce(
    String kind,
    String id,
    Future<void> Function() apply,
  ) => db.transaction(() async {
    if (await wasApplied(kind, id)) return false;
    await apply();
    await db.customStatement(
      'INSERT INTO processed_watch_commands (kind, command_id, applied_at) VALUES (?, ?, ?)',
      [kind, id, DateTime.now().millisecondsSinceEpoch],
    );
    return true;
  });
}

/// New watches preserve the local calendar day even when delivered after
/// midnight or after travelling. Legacy Android commands retain today's date.
DateTime watchCommandDate(Map<String, dynamic> command, {DateTime? now}) {
  final day = command['localDate'] as String?;
  if (day != null) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const FormatException('Invalid watch localDate');
    }
    final parsed = DateTime.parse(day);
    final canonical =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    if (canonical != day) {
      throw const FormatException('Invalid watch localDate');
    }
    return parsed;
  }
  final created = command['createdAtEpochMs'];
  if (created is num && created > 0) {
    return DateTime.fromMillisecondsSinceEpoch(created.toInt());
  }
  return now ?? DateTime.now();
}
