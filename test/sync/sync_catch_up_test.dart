import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_service.dart';

import '../support/test_database.dart';
import 'fake_sync_backend_service.dart';

/// How quickly a change on one device gets to the other:
///
/// * coming back to the app (or a browser tab) pulls straight away, because
///   realtime hints sent while it was away are never replayed;
/// * a hint that lands while a pull is already running is not dropped - one
///   more pull follows;
/// * a local write is pushed a couple of seconds later instead of waiting for
///   the next 20-second tick.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-1';

  late AppDatabase db;
  late _CountingBackend backend;
  late SyncService sync;

  setUp(() async {
    db = await openTestDatabase();
    backend = _CountingBackend();
    sync = SyncService(db: db, backend: backend);
  });

  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  Future<void> addGym(String name) =>
      db.into(db.gyms).insert(GymsCompanion.insert(name: name)).then((_) {});

  group('syncOnResume', () {
    test('pushes pending edits and pulls remote changes', () async {
      await sync.start(userId);
      backend.pullCalls = 0;
      await addGym('Garage');

      await sync.syncOnResume();

      expect(backend.upsertCalls.where((c) => c.$1 == 'gyms'), hasLength(1));
      expect(backend.pullCalls, greaterThan(0));
    });

    test('does nothing before sign-in', () async {
      await sync.syncOnResume();
      expect(backend.pullCalls, 0);
    });

    test('a second resume right after the first is ignored', () async {
      await sync.start(userId);
      await sync.syncOnResume();
      final afterFirst = backend.pullCalls;

      await sync.syncOnResume();

      expect(backend.pullCalls, afterFirst);
    });
  });

  group('a hint during a pull', () {
    test('is not dropped: one more pull follows', () async {
      await sync.start(userId);
      final perCycle = backend.pullCalls;
      expect(perCycle, greaterThan(0));
      backend.pullCalls = 0;

      // Hold the running pull open, as a slow network would.
      backend.gate = Completer<void>();
      final running = sync.pullAll();
      await backend.firstPullStarted.future;

      backend.emitHint('workout_sessions');
      backend.emitHint('set_entries');
      await Future<void>.delayed(Duration.zero);
      backend.gate!.complete();
      await running;

      // The follow-up is fired, not awaited: wait for it to finish.
      await _eventually(() => backend.pullCalls >= 2 * perCycle);
      expect(
        backend.pullCalls,
        2 * perCycle,
        reason: 'two hints coalesce into a single extra pull, not two',
      );
    });
  });

  group('a local write', () {
    test(
      'is pushed shortly after, without waiting for the 20 s tick',
      () async {
        await sync.start(userId);
        expect(backend.upsertCalls.where((c) => c.$1 == 'gyms'), isEmpty);

        await addGym('Garage');
        // Nothing yet: the push is debounced.
        expect(backend.upsertCalls.where((c) => c.$1 == 'gyms'), isEmpty);

        await _eventually(
          () => backend.upsertCalls.any((c) => c.$1 == 'gyms'),
          timeout: const Duration(seconds: 6),
        );
      },
    );

    test('keeps waiting while edits keep coming', () async {
      await sync.start(userId);

      await addGym('Garage');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await addGym('Basement');
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // 2.4 s after the first edit: it would have gone up at 2 s had the
      // second edit not restarted the wait.
      expect(backend.upsertCalls.where((c) => c.$1 == 'gyms'), isEmpty);

      await _eventually(
        () => backend.upsertCalls.where((c) => c.$1 == 'gyms').length == 2,
        timeout: const Duration(seconds: 6),
      );
    });

    test('nothing is scheduled after sign-out', () async {
      await sync.start(userId);
      await sync.stop();
      backend.upsertCalls.clear();

      await addGym('Garage');
      await Future<void>.delayed(const Duration(milliseconds: 2600));

      expect(backend.upsertCalls, isEmpty);
    });
  });
}

Future<void> _eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A fake cloud that counts pulls and can hold one open.
class _CountingBackend extends FakeSyncBackendService {
  int pullCalls = 0;

  Completer<void>? gate;
  final firstPullStarted = Completer<void>();

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) async {
    pullCalls++;
    final held = gate;
    if (held != null) {
      if (!firstPullStarted.isCompleted) firstPullStarted.complete();
      await held.future;
    }
    return super.pull(table, userId: userId, since: since);
  }
}
