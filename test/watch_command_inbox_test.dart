import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/watch_command_inbox.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() async {
    db = await openTestDatabase();
  });
  tearDown(() async {
    await db.close();
  });

  test(
    'receipt survives a new inbox instance and prevents a repeated write',
    () async {
      await db.customStatement(
        'CREATE TABLE watch_test_counter (value INTEGER)',
      );
      Future<void> write() =>
          db.customStatement('INSERT INTO watch_test_counter VALUES (1)');
      expect(
        await WatchCommandInbox(db).applyOnce('water', 'same-command', write),
        isTrue,
      );
      expect(
        await WatchCommandInbox(db).applyOnce('water', 'same-command', write),
        isFalse,
      );
      expect(
        (await db.customSelect('SELECT * FROM watch_test_counter').get())
            .length,
        1,
      );
    },
  );

  test(
    'failed business write rolls back both rows and receipt; retry works',
    () async {
      await db.customStatement(
        'CREATE TABLE watch_test_counter (value INTEGER)',
      );
      final inbox = WatchCommandInbox(db);
      await expectLater(
        inbox.applyOnce('food', 'retry', () async {
          await db.customStatement('INSERT INTO watch_test_counter VALUES (1)');
          throw StateError('interrupted before commit');
        }),
        throwsStateError,
      );
      expect(await inbox.wasApplied('food', 'retry'), isFalse);
      expect(
        await db.customSelect('SELECT * FROM watch_test_counter').get(),
        isEmpty,
      );
      await inbox.applyOnce(
        'food',
        'retry',
        () => db.customStatement('INSERT INTO watch_test_counter VALUES (1)'),
      );
      expect(await inbox.wasApplied('food', 'retry'), isTrue);
    },
  );

  test(
    'same ID in independent command kinds is not incorrectly deduplicated',
    () async {
      final inbox = WatchCommandInbox(db);
      await inbox.applyOnce('water', 'id', () async {});
      expect(await inbox.applyOnce('food', 'id', () async {}), isTrue);
    },
  );

  test(
    'calendar day survives offline delivery, midnight and timezone changes',
    () {
      expect(
        watchCommandDate({
          'localDate': '2026-10-20',
          'createdAtEpochMs': 1,
        }, now: DateTime(2026, 10, 21)),
        DateTime(2026, 10, 20),
      );
      expect(
        watchCommandDate({}, now: DateTime(2026, 10, 21)),
        DateTime(2026, 10, 21),
      );
      expect(
        () => watchCommandDate({'localDate': '2026-02-30'}),
        throwsFormatException,
      );
      expect(
        () => watchCommandDate({'localDate': 'yesterday'}),
        throwsFormatException,
      );
    },
  );

  test(
    'watch transport tables remain local and are not queued for cloud sync',
    () async {
      await WatchCommandInbox(db).applyOnce('macro', 'local', () async {});
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name = ?",
            variables: [Variable('processed_watch_commands')],
          )
          .get();
      expect(rows, isEmpty);
    },
  );
}
