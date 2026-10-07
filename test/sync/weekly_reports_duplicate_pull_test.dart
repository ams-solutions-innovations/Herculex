// Phase 29 open question 3: what does the real SyncService pull path do when a
// remote weekly_reports row collides on (iso_year, iso_week) with a local row
// under a different sync_uuid? That is what two devices that each generated
// the same week produce.
import 'package:drift/drift.dart' hide isNotNull, isNull;
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
  const userId = 'user-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeSyncBackendService();
    sync = SyncService(db: db, backend: backend);
  });

  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  Map<String, dynamic> remoteReport(String uuid, int year, int week) => {
    'id': uuid,
    'user_id': userId,
    'iso_year': year,
    'iso_week': week,
    'week_start_iso': '2026-09-28',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'payload_version': 1,
    'payload_json': '{}',
    'narrative_json': null,
    'narrative_attempts': 0,
    'knowledge_version': null,
    'model_version': null,
    'tdee_decision': null,
    'tdee_decision_kcal': null,
    'viewed_at': null,
    'deleted_at': null,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  Future<int> localCount(int year, int week) async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS c FROM weekly_reports '
                'WHERE iso_year = ? AND iso_week = ?',
                variables: [Variable(year), Variable(week)],
              )
              .getSingle())
          .read<int>('c');

  test('a duplicate (iso_year, iso_week) pull is recorded', () async {
    await sync.start(userId);

    await db
        .into(db.weeklyReports)
        .insert(
          WeeklyReportsCompanion.insert(
            isoYear: 2026,
            isoWeek: 40,
            weekStartIso: '2026-09-28',
            payloadJson: '{}',
          ),
        );
    final localUuid = (await db.select(db.weeklyReports).getSingle()).syncUuid;

    // The duplicate is seeded BEFORE the unrelated week and before a row of a
    // table that is pulled later in syncTableOrder, so an aborted cycle is
    // visible in both.
    backend.seedRemoteRow('weekly_reports', remoteReport('dup-uuid', 2026, 40));
    backend.seedRemoteRow(
      'weekly_reports',
      remoteReport('other-week-uuid', 2026, 39),
    );
    backend.seedRemoteRow('daily_summaries', {
      'id': 'later-table-uuid',
      'user_id': userId,
      'date_iso': '2026-09-28',
      'water_ml': 0,
      'weigh_in_kg': null,
      'notes': null,
      'deleted_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    Object? thrown;
    try {
      await sync.pullAll();
    } catch (e) {
      thrown = e;
    }

    // RESULT (with the local unique key dropped, the plan-05 fallback):
    // nothing throws, both (2026, 40) rows land, the other week and the
    // later table are applied, and the cycle ends clean. Readers must pick
    // deterministically; the repository enforces one-per-week on insert.
    expect(thrown, isNull);
    expect(await localCount(2026, 40), 2);
    expect(await localCount(2026, 39), 1);
    expect((await db.select(db.dailySummaries).get()).map((r) => r.syncUuid), [
      'later-table-uuid',
    ]);
    expect(
      (await db.select(db.weeklyReports).get()).map((r) => r.syncUuid),
      containsAll([localUuid, 'dup-uuid', 'other-week-uuid']),
    );
    expect(sync.state.lastError, isNull);
  });
}
