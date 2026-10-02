// Phase 23 (PHYS-01): guards that the four physique tables are fully
// registered for sync. Half-registration fails silently (rows never leave the
// device, or the outbox never sees them), so each registration point is
// asserted, and an insert must actually produce an outbox row.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';

import 'support/test_database.dart';

const _tables = <String>[
  'physique_goals',
  'physique_assessments',
  'physique_roadmap_phases',
  'physique_photos',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all four physique tables are in the sync registries', () {
    for (final table in _tables) {
      expect(syncedTableNames, contains(table));
      expect(syncTableOrder, contains(table));
      expect(syncTableSpecsByName[table], isNotNull, reason: table);
    }
  });

  test('specs carry the expected datetime columns and foreign keys', () {
    expect(
      syncTableSpecsByName['physique_goals']!.dateTimeColumns,
      containsAll(<String>[
        'started_at',
        'archived_at',
        'roadmap_accepted_at',
        'advance_snoozed_until',
      ]),
    );
    expect(
      syncTableSpecsByName['physique_assessments']!.dateTimeColumns,
      contains('assessed_at'),
    );
    expect(
      syncTableSpecsByName['physique_roadmap_phases']!.dateTimeColumns,
      containsAll(<String>['started_at', 'completed_at']),
    );
    expect(
      syncTableSpecsByName['physique_photos']!.dateTimeColumns,
      contains('taken_at'),
    );

    String fkSummary(String table) => syncTableSpecsByName[table]!.fkFields
        .whereType<SimpleFk>()
        .map((f) => '${f.localColumn}->${f.parentTable}')
        .join(',');
    expect(fkSummary('physique_goals'), isEmpty);
    expect(fkSummary('physique_assessments'), 'goal_id->physique_goals');
    expect(fkSummary('physique_roadmap_phases'), 'goal_id->physique_goals');
    expect(
      fkSummary('physique_photos'),
      'goal_id->physique_goals,assessment_id->physique_assessments',
    );
  });

  test('parents are ordered before children', () {
    final order = syncTableOrder;
    int at(String t) => order.indexOf(t);
    expect(at('physique_goals'), lessThan(at('physique_assessments')));
    expect(at('physique_goals'), lessThan(at('physique_roadmap_phases')));
    expect(at('physique_goals'), lessThan(at('physique_photos')));
    expect(at('physique_assessments'), lessThan(at('physique_photos')));

    final backfill = syncedTableNames;
    expect(
      backfill.indexOf('physique_goals'),
      lessThan(backfill.indexOf('physique_assessments')),
    );
    expect(
      backfill.indexOf('physique_assessments'),
      lessThan(backfill.indexOf('physique_photos')),
    );
  });

  test('a fresh database has the sync_uuid unique indexes', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    for (final table in _tables) {
      final index = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_sync_uuid_$table'",
          )
          .get();
      expect(index, hasLength(1), reason: table);
    }
  });

  Future<List<String>> outboxOps(AppDatabase db, String table) async {
    final ops = await db
        .customSelect(
          'SELECT entity_id, operation FROM pending_sync_ops '
          "WHERE entity_type = '$table'",
        )
        .get();
    return [
      for (final o in ops)
        '${o.read<String>('operation')}:'
            '${o.read<String>('entity_id')}',
    ];
  }

  test('inserting one row per table enqueues an outbox upsert', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final goalId = await db
        .into(db.physiqueGoals)
        .insert(PhysiqueGoalsCompanion.insert());
    final assessmentId = await db
        .into(db.physiqueAssessments)
        .insert(
          PhysiqueAssessmentsCompanion.insert(
            goalId: goalId,
            kind: 'analysis',
            dateIso: '2026-10-02',
          ),
        );
    await db
        .into(db.physiqueRoadmapPhases)
        .insert(
          PhysiqueRoadmapPhasesCompanion.insert(
            goalId: goalId,
            orderIndex: 0,
            phaseType: 'cut',
            plannedWeeks: 8,
          ),
        );
    await db
        .into(db.physiquePhotos)
        .insert(
          PhysiquePhotosCompanion.insert(
            goalId: goalId,
            assessmentId: Value(assessmentId),
            role: 'baseline',
            pose: 'front',
            dateIso: '2026-10-02',
            relativePath: 'physique/front.jpg',
          ),
        );

    final uuids = <String, String>{
      'physique_goals':
          (await db.select(db.physiqueGoals).getSingle()).syncUuid!,
      'physique_assessments':
          (await db.select(db.physiqueAssessments).getSingle()).syncUuid!,
      'physique_roadmap_phases':
          (await db.select(db.physiqueRoadmapPhases).getSingle()).syncUuid!,
      'physique_photos':
          (await db.select(db.physiquePhotos).getSingle()).syncUuid!,
    };

    for (final table in _tables) {
      final ops = await db
          .customSelect(
            'SELECT entity_id, operation FROM pending_sync_ops '
            "WHERE entity_type = '$table'",
          )
          .get();
      expect(ops, hasLength(1), reason: table);
      expect(ops.single.read<String>('entity_id'), uuids[table]);
      expect(ops.single.read<String>('operation'), 'upsert');
    }
  });

  test('a photos-only legacy goal is storable with null targets', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    await db
        .into(db.physiqueGoals)
        .insert(
          PhysiqueGoalsCompanion.insert(source: const Value('legacy_import')),
        );
    final goal = await db.select(db.physiqueGoals).getSingle();
    expect(goal.estimatedMonths, isNull);
    expect(goal.targetBfPercent, isNull);
    expect(goal.targetAestheticStyle, '');
  });

  test('soft-deleting an assessment still enqueues an upsert', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final goalId = await db
        .into(db.physiqueGoals)
        .insert(PhysiqueGoalsCompanion.insert());
    await db
        .into(db.physiqueAssessments)
        .insert(
          PhysiqueAssessmentsCompanion.insert(
            goalId: goalId,
            kind: 'checkin',
            dateIso: '2026-10-02',
          ),
        );
    await db.customStatement('DELETE FROM pending_sync_ops');

    await db.customStatement(
      "UPDATE physique_assessments SET deleted_at = '2026-10-03T00:00:00Z'",
    );

    final ops = await outboxOps(db, 'physique_assessments');
    expect(ops, hasLength(1));
    expect(ops.single, startsWith('upsert:'));
  });
}
