import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'fake_sync_backend_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeSyncBackendService backend;
  late SyncService sync;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeSyncBackendService();
    sync = SyncService(db: db, backend: backend);
    await sync.start('user-1');
  });
  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  test(
    'remote nutrition writes notify live readers and ignore future server fields',
    () async {
      expect(await db.select(db.nutritionTargets).get(), isEmpty);
      final update = db
          .select(db.nutritionTargets)
          .watch()
          .firstWhere((rows) => rows.isNotEmpty);
      backend.seedRemoteRow('nutrition_targets', {
        'id': 'remote-target',
        'user_id': 'user-1',
        'label': 'Scheduled target',
        'applies_to': 'global',
        'effective_from_date_iso': '2026-10-22',
        'kcal': 2500,
        'protein_g': 160,
        'carbs_g': 300,
        'fat_g': 80,
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 1))
            .toIso8601String(),
        'future_server_metadata': 'ignored by this app version',
      });
      await sync.pullAll();
      final rows = await update.timeout(const Duration(seconds: 3));
      expect(rows.single.effectiveFromDateIso, '2026-10-22');
      expect(rows.single.syncUuid, 'remote-target');
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    },
  );

  test('remote deletion notifies existing live readers', () async {
    backend.seedRemoteRow('nutrition_targets', {
      'id': 'remote-deleted-target',
      'user_id': 'user-1',
      'label': 'To delete',
      'applies_to': 'global',
      'effective_from_date_iso': '2026-10-21',
      'kcal': 2400,
      'protein_g': 160,
      'carbs_g': 275,
      'fat_g': 80,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await sync.pullAll();
    expect(await db.select(db.nutritionTargets).get(), hasLength(1));
    final deletion = db
        .select(db.nutritionTargets)
        .watch()
        .firstWhere((rows) => rows.isEmpty);
    await backend.delete('nutrition_targets', 'remote-deleted-target');
    await sync.pullAll();
    expect(await deletion.timeout(const Duration(seconds: 3)), isEmpty);
    expect(await db.select(db.pendingSyncOps).get(), isEmpty);
  });
  test(
    'same-start nutrition targets from two devices converge on the server identity',
    () async {
      await db.customStatement(
        "INSERT INTO nutrition_targets(label,kcal,protein_g,carbs_g,fat_g,applies_to,effective_from_date_iso,sync_uuid) VALUES('Local',2400,160,275,80,'global','2026-10-22','device-a')",
      );
      await db.customStatement('DELETE FROM pending_sync_ops');
      final originalId = (await db.select(db.nutritionTargets).getSingle()).id;
      backend.seedRemoteRow('nutrition_targets', {
        'id': 'device-b',
        'user_id': 'user-1',
        'label': 'Server target',
        'applies_to': 'global',
        'effective_from_date_iso': '2026-10-22',
        'kcal': 2500,
        'protein_g': 160,
        'carbs_g': 300,
        'fat_g': 80,
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 1))
            .toIso8601String(),
      });
      await sync.pullAll();
      final result = await db.select(db.nutritionTargets).getSingle();
      expect(result.id, originalId);
      expect(result.syncUuid, 'device-b');
      expect(result.kcal, 2500);
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    },
  );

  test('a pending target edit wins over another device until pushed', () async {
    await db.customStatement(
      "INSERT INTO nutrition_targets(label,kcal,protein_g,carbs_g,fat_g,applies_to,effective_from_date_iso,sync_uuid) VALUES('Offline edit',2400,160,275,80,'global','2026-10-22','offline-device')",
    );
    backend.seedRemoteRow('nutrition_targets', {
      'id': 'remote-device',
      'user_id': 'user-1',
      'label': 'Older remote',
      'applies_to': 'global',
      'effective_from_date_iso': '2026-10-22',
      'kcal': 2500,
      'protein_g': 160,
      'carbs_g': 300,
      'fat_g': 80,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await sync.pullAll();
    expect((await db.select(db.nutritionTargets).getSingle()).kcal, 2400);
    expect(await db.select(db.pendingSyncOps).get(), isNotEmpty);
    await sync.pushOnce();
    expect(backend.remoteRows['nutrition_targets'], hasLength(1));
    expect(backend.remoteRows['nutrition_targets']!.single['kcal'], 2400);
    await sync.pullAll();
    expect(
      (await db.select(db.nutritionTargets).getSingle()).syncUuid,
      'offline-device',
    );
  });
}
