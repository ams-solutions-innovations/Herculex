import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the physique v47 migration (schema chore 5, Phase 23).
///
/// A column that exists locally but not in Postgres makes PostgREST answer
/// PGRST204 and the outbox quarantines the row after 8 attempts, which looks
/// fine locally. The parity test derives the expected column list from the
/// drift definitions so the two cannot drift apart silently.
void main() {
  const path = 'supabase/migrations/20261002000000_physique_v47.sql';

  const tableClasses = <String, String>{
    'physique_goals': 'PhysiqueGoals',
    'physique_assessments': 'PhysiqueAssessments',
    'physique_roadmap_phases': 'PhysiqueRoadmapPhases',
    'physique_photos': 'PhysiquePhotos',
  };

  String readRaw() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    return file.readAsStringSync();
  }

  // Collapse whitespace so assertions do not depend on line wrapping.
  String normalise(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String readSql() => normalise(readRaw());

  /// The statements of one table: from its `create table` to the next one
  /// (or end of file), header excluded.
  Map<String, String> blocks() {
    final sql = readSql();
    final parts = sql.split('create table ');
    expect(parts.length, 5, reason: 'header + four tables');
    return {
      for (final part in parts.skip(1))
        part.substring(0, part.indexOf(' ')): part,
    };
  }

  test('creates the four tables parent-first', () {
    final sql = readSql();
    final order = [
      for (final t in tableClasses.keys) sql.indexOf('create table $t '),
    ];
    for (final i in order) {
      expect(i, greaterThan(-1));
    }
    expect(order[0], lessThan(order[1]));
    expect(order[0], lessThan(order[2]));
    expect(order[1], lessThan(order[3]));
    expect('create table physique_'.allMatches(sql).length, 4);
  });

  test('every table has the exact column definitions', () {
    final b = blocks();
    const expected = <String, List<String>>{
      'physique_goals': [
        'id uuid primary key',
        'user_id uuid not null references auth.users(id) on delete cascade',
        "status text not null default 'active'",
        "source text not null default 'ai_analysis'",
        "target_aesthetic_style text not null default ''",
        "timeframe_range text not null default ''",
        'estimated_months integer,',
        'target_bf_percent double precision,',
        'start_weight_kg double precision',
        'start_bf_percent double precision',
        'started_at timestamptz not null default now()',
        'archived_at timestamptz',
        'roadmap_accepted_at timestamptz',
        'advance_snoozed_until timestamptz',
        'updated_at timestamptz not null default now()',
        'deleted_at timestamptz',
      ],
      'physique_assessments': [
        'id uuid primary key',
        'user_id uuid not null references auth.users(id) on delete cascade',
        'goal_id uuid not null references public.physique_goals(id) '
            'on delete cascade',
        'kind text not null',
        'assessed_at timestamptz not null default now()',
        'date_iso text not null',
        'weight_kg double precision',
        'current_bf_percent double precision',
        'bf_range_min double precision',
        'bf_range_max double precision',
        "confidence text not null default 'unknown'",
        'verdict text,',
        'direction_band_low double precision',
        'direction_band_high double precision',
        'reason text,',
        'limitations_json text',
        "source text not null default 'ai'",
        'model_version text',
        'knowledge_version text',
        'summary_json text',
        'updated_at timestamptz not null default now()',
        'deleted_at timestamptz',
      ],
      'physique_roadmap_phases': [
        'id uuid primary key',
        'user_id uuid not null references auth.users(id) on delete cascade',
        'goal_id uuid not null references public.physique_goals(id) '
            'on delete cascade',
        'order_index integer not null',
        'phase_type text not null',
        'planned_weeks integer not null',
        'target_weight_kg double precision',
        'target_bf_percent double precision',
        'weekly_rate_kg double precision',
        'tempo_capped boolean not null default false',
        "status text not null default 'upcoming'",
        'started_at timestamptz,',
        'completed_at timestamptz,',
        'updated_at timestamptz not null default now()',
        'deleted_at timestamptz',
      ],
      'physique_photos': [
        'id uuid primary key',
        'user_id uuid not null references auth.users(id) on delete cascade',
        'goal_id uuid not null references public.physique_goals(id) '
            'on delete cascade',
        'assessment_id uuid references public.physique_assessments(id) '
            'on delete set null',
        'role text not null',
        'pose text not null',
        'date_iso text not null',
        'taken_at timestamptz not null default now()',
        'relative_path text not null',
        'blurred boolean not null default false',
        "source text not null default 'capture'",
        'legacy_ref text,',
        'updated_at timestamptz not null default now()',
        'deleted_at timestamptz',
      ],
    };
    for (final entry in expected.entries) {
      for (final column in entry.value) {
        expect(
          b[entry.key],
          contains(column),
          reason: '${entry.key} missing "$column"',
        );
      }
    }
  });

  test('goal_id and assessment_id foreign keys have the right actions', () {
    final b = blocks();
    for (final t in const [
      'physique_assessments',
      'physique_roadmap_phases',
      'physique_photos',
    ]) {
      expect(
        b[t],
        contains(
          'goal_id uuid not null references public.physique_goals(id) '
          'on delete cascade',
        ),
      );
    }
    expect(
      b['physique_photos'],
      contains(
        'assessment_id uuid references public.physique_assessments(id) '
        'on delete set null',
      ),
    );
    expect(
      b['physique_photos'],
      isNot(contains('assessment_id uuid not null')),
    );
  });

  test('legacy goal columns are nullable; style defaults to empty', () {
    final goals = blocks()['physique_goals']!;
    final months = RegExp(r'estimated_months [^,]*,').firstMatch(goals)!;
    final bf = RegExp(r'target_bf_percent [^,]*,').firstMatch(goals)!;
    expect(months.group(0), isNot(contains('not null')));
    expect(bf.group(0), isNot(contains('not null')));
    expect(goals, contains("target_aesthetic_style text not null default ''"));
  });

  test('is owner-only: RLS enabled and 16 user_id = auth.uid() policies', () {
    final sql = readSql();
    expect('create policy'.allMatches(sql).length, 16);
    for (final t in tableClasses.keys) {
      expect(sql, contains('alter table $t enable row level security'));
      for (final op in const ['select', 'insert', 'update', 'delete']) {
        expect(sql, contains('${t}_${op}_own'));
      }
      expect(sql, contains('on $t for select using (user_id = auth.uid())'));
      expect(
        sql,
        contains('on $t for insert with check (user_id = auth.uid())'),
      );
      expect(
        sql,
        contains(
          'on $t for update using (user_id = auth.uid()) '
          'with check (user_id = auth.uid())',
        ),
      );
      expect(sql, contains('on $t for delete using (user_id = auth.uid())'));
    }
  });

  test('wires triggers, realtime publication and the pull index', () {
    final sql = readSql();
    for (final t in tableClasses.keys) {
      expect(sql, contains('t_set_updated_at_$t'));
      expect(sql, contains('t_record_tombstone_$t'));
      expect(
        sql,
        contains('alter publication supabase_realtime add table public.$t'),
      );
      expect(
        sql,
        contains(
          'create index if not exists ${t}_user_updated_idx '
          'on public.$t (user_id, updated_at, id)',
        ),
      );
    }
    expect(sql, contains('execute function set_updated_at()'));
    expect(sql, contains('execute function public.record_sync_tombstone()'));
  });

  test('no column constraints and no image bytes (D-09)', () {
    final sql = readSql();
    expect(RegExp(r'(?<!with )check\s*\(').hasMatch(sql), isFalse);
    expect(sql, isNot(contains('constraint')));
    expect(sql, isNot(contains('bytea')));
  });

  test('header names the right project and says not applied', () {
    final sql = readSql();
    expect(sql, contains('ldzgyzigvbwofbswitrv'));
    expect(sql, contains('not applied'));
    expect(sql, contains('0015'));
    expect(sql, contains('0016'));
  });

  test('every local drift column exists remotely (snake_case parity)', () {
    final tables = File('lib/data/local/tables.dart').readAsStringSync();
    expect(tables, contains('mixin SyncColumns'));

    String snake(String camel) => camel.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );

    final b = blocks();
    for (final entry in tableClasses.entries) {
      final classMatch = RegExp(
        'class ${entry.value} extends Table[^{]*\\{(.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(tables);
      expect(classMatch, isNotNull, reason: '${entry.value} class not found');

      final local = <String>{
        for (final m in RegExp(
          r'get (\w+)\s*=>?',
        ).allMatches(classMatch!.group(1)!))
          snake(m.group(1)!),
        // SyncColumns / SyncTombstone contributions. sync_uuid and
        // synced_at are local-only bookkeeping: sync_uuid maps to the
        // remote `id` and synced_at is never sent.
        'updated_at',
        'deleted_at',
      };
      expect(local, isNot(contains('sync_uuid')));
      expect(local, isNot(contains('synced_at')));
      expect(local.length, greaterThan(5));

      // Match the column as a definition at the start of a column line
      // ("<name> <type>") so prose in the header cannot satisfy the check.
      for (final column in local) {
        expect(
          RegExp('(\\( |, )$column ').hasMatch(b[entry.key]!),
          isTrue,
          reason: 'remote ${entry.key} is missing local column "$column"',
        );
      }
    }
  });
}
