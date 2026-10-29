import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/catalogue_ref_prefetcher.dart';
import 'package:herculex/data/sync/sync_service.dart';

import 'fake_sync_backend_service.dart';

class _RecordingPrefetcher implements CatalogueRefPrefetcher {
  final requested = <Set<String>>[];
  bool fail = false;

  @override
  Future<void> ensureFoods(Set<String> catalogueRefs) async {
    requested.add(catalogueRefs);
    if (fail) throw Exception('offline');
  }
}

/// Web track W2: a row the local schema rejects must not stop the rest of
/// the account from syncing, and the first full pull is what lets a fresh
/// browser open the account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeSyncBackendService backend;
  late SyncService sync;
  const userId = 'user-1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeSyncBackendService();
    sync = SyncService(db: db, backend: backend);
  });

  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  String at(int minutes) => DateTime.utc(
    2026,
    10,
    27,
    9,
  ).add(Duration(minutes: minutes)).toIso8601String();

  Future<String?> cursorFor(String table) async {
    final row = await db
        .customSelect(
          'SELECT cursor_iso FROM sync_cursors WHERE entity_type = ?',
          variables: [Variable(table)],
        )
        .getSingleOrNull();
    return row?.data['cursor_iso'] as String?;
  }

  Map<String, dynamic> gym(String id, String? name, String updatedAt) => {
    'id': id,
    'user_id': userId,
    'name': name,
    'is_default': 0,
    'created_at': updatedAt,
    'updated_at': updatedAt,
    'deleted_at': null,
  };

  test(
    'one unappliable row does not stop later rows or later tables',
    () async {
      backend
        ..seedRemoteRow('gyms', gym('good-before', 'Before', at(1)))
        // NOT NULL locally: this row can never be applied as-is.
        ..seedRemoteRow('gyms', gym('broken', null, at(2)))
        ..seedRemoteRow('gyms', gym('good-after', 'After', at(3)))
        ..seedRemoteRow('body_measurements', {
          'id': 'weight-1',
          'user_id': userId,
          'date_iso': '2026-10-27',
          'metric': 'bodyweight',
          'value': 81.2,
          'updated_at': at(4),
          'deleted_at': null,
        });

      await sync.start(userId);

      final names = (await db.select(db.gyms).get()).map((g) => g.name).toSet();
      expect(names, containsAll(['Before', 'After']));
      expect(await db.select(db.bodyMeasurements).get(), hasLength(1));

      // The gyms cursor stops before the broken row so it is retried; the
      // later table's cursor moves on as normal.
      expect(DateTime.parse((await cursorFor('gyms'))!), DateTime.parse(at(1)));
      expect(
        DateTime.parse((await cursorFor('body_measurements'))!),
        DateTime.parse(at(4)),
      );
      expect(sync.state.lastError, contains('gyms'));
    },
  );

  test('the first complete pull marks the account as restored', () async {
    expect(sync.initialPullDone, isFalse);
    final seen = <bool>[];
    final sub = sync.initialPullDoneStream.listen(seen.add);

    await sync.start(userId);
    await pumpEventQueue();

    expect(sync.initialPullDone, isTrue);
    expect(seen, [false, true]);
    await sub.cancel();
  });

  test('a failed fetch leaves the account unrestored', () async {
    backend.failPulls = true;
    await sync.start(userId);
    expect(sync.initialPullDone, isFalse);

    backend.failPulls = false;
    await sync.pullAll();
    expect(sync.initialPullDone, isTrue);
  });

  test('the marker survives a restart for the same account', () async {
    await sync.start(userId);
    expect(sync.initialPullDone, isTrue);
    await sync.stop();
    expect(sync.initialPullDone, isFalse);

    backend.failPulls = true;
    await sync.start(userId);
    expect(sync.initialPullDone, isTrue);
  });

  group('catalogue prefetch', () {
    late _RecordingPrefetcher prefetcher;

    setUp(() async {
      await sync.dispose();
      prefetcher = _RecordingPrefetcher();
      sync = SyncService(
        db: db,
        backend: backend,
        cataloguePrefetcher: prefetcher,
      );
    });

    Map<String, dynamic> entry(String id, String ref) => {
      'id': id,
      'user_id': userId,
      'food_catalogue_ref': ref,
      'date_iso': '2026-10-27',
      'meal': 'breakfast',
      'servings': 1.0,
      'logged_at': at(5),
      'updated_at': at(5),
      'deleted_at': null,
    };

    test('asks for every catalogue food the pulled entries use', () async {
      backend
        ..seedRemoteRow('food_entries', entry('e1', 'eu-101'))
        ..seedRemoteRow('food_entries', entry('e2', 'eu-202'));
      await sync.start(userId);
      expect(
        prefetcher.requested,
        contains(unorderedEquals(['eu-101', 'eu-202'])),
      );
    });

    test('a failed prefetch holds the table back and the account '
        'unrestored', () async {
      prefetcher.fail = true;
      backend.seedRemoteRow('food_entries', entry('e1', 'eu-101'));
      await sync.start(userId);

      expect(await db.select(db.foodEntries).get(), isEmpty);
      expect(await cursorFor('food_entries'), isNull);
      expect(sync.initialPullDone, isFalse);
    });
  });

  test('a different account starts unrestored', () async {
    await sync.start(userId);
    await sync.stop();

    backend.failPulls = true;
    await sync.start('user-2');
    expect(sync.initialPullDone, isFalse);
  });
}
