import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the herculex_ai_program_briefs migration (schema
/// chore 5, plan 27-10).
///
/// A column that exists locally but not in Postgres makes PostgREST answer
/// PGRST204 and the outbox quarantines the row after 8 attempts, which looks
/// fine locally. The parity test derives the expected column list from the
/// drift definition so the two cannot drift apart silently.
void main() {
  const path =
      'supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql';

  String readSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    // Collapse whitespace so assertions do not depend on line wrapping.
    return file.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  test(
    'creates herculex_ai_program_briefs with the exact column definitions',
    () {
      final sql = readSql();
      expect(sql, contains('create table herculex_ai_program_briefs'));
      for (final column in const [
        'id uuid primary key',
        'user_id uuid not null references auth.users(id) on delete cascade',
        'program_id uuid not null references public.programs(id) on delete cascade',
        'brief_json text not null',
        "source text not null default 'herculex_ai'",
        'knowledge_version text',
        'model_version text',
        'confirmed_at timestamptz not null default now()',
        'active boolean not null default true',
        'updated_at timestamptz not null default now()',
        'deleted_at timestamptz',
      ]) {
        expect(sql, contains(column));
      }
    },
  );

  test('is owner-only: RLS enabled and four user_id = auth.uid() policies', () {
    final sql = readSql();
    expect(
      sql,
      contains(
        'alter table herculex_ai_program_briefs enable row level security',
      ),
    );
    for (final op in const ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('herculex_ai_program_briefs_${op}_own'));
    }
    expect(
      sql,
      contains(
        'on herculex_ai_program_briefs for insert '
        'with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains(
        'on herculex_ai_program_briefs for update using (user_id = auth.uid()) '
        'with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains(
        'on herculex_ai_program_briefs for select using (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains(
        'on herculex_ai_program_briefs for delete using (user_id = auth.uid())',
      ),
    );
    expect('create policy'.allMatches(sql).length, 4);
  });

  test('wires triggers, realtime publication and the pull index', () {
    final sql = readSql();
    expect(sql, contains('t_set_updated_at_herculex_ai_program_briefs'));
    expect(sql, contains('execute function set_updated_at()'));
    expect(sql, contains('t_record_tombstone_herculex_ai_program_briefs'));
    expect(sql, contains('execute function public.record_sync_tombstone()'));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table '
        'public.herculex_ai_program_briefs',
      ),
    );
    expect(
      sql,
      contains(
        'create index if not exists herculex_ai_program_briefs_user_updated_idx '
        'on public.herculex_ai_program_briefs (user_id, updated_at, id)',
      ),
    );
  });

  test(
    'does not constrain source/knowledge_version/model_version vocabulary',
    () {
      final sql = readSql();
      // Only RLS `with check (...)` clauses are allowed; no column
      // constraint. D-08's provenance columns are free text, validated (if
      // at all) at the Dart repository boundary, same as tdee_estimates'
      // method/confidence precedent.
      expect(RegExp(r'(?<!with )check\s*\(').hasMatch(sql), isFalse);
      expect(sql, isNot(contains('constraint')));
    },
  );

  test(
    'header names the right project and states no 0015/0016 ordering dependency',
    () {
      final sql = readSql();
      expect(sql, contains('ldzgyzigvbwofbswitrv'));
      expect(sql, contains('0015'));
      expect(sql, contains('0016'));
    },
  );

  test('every local drift column exists remotely (snake_case parity)', () {
    final sql = readSql();
    final tables = File('lib/data/local/tables.dart').readAsStringSync();

    final classMatch = RegExp(
      r'class HerculexAiProgramBriefs extends Table[^{]*\{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(tables);
    expect(
      classMatch,
      isNotNull,
      reason: 'HerculexAiProgramBriefs class not found',
    );

    String snake(String camel) => camel.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );

    final local = <String>{
      for (final m in RegExp(
        r'get (\w+)\s*=>?',
      ).allMatches(classMatch!.group(1)!))
        snake(m.group(1)!),
      // SyncColumns / SyncTombstone contributions. sync_uuid and synced_at
      // are local-only bookkeeping: SyncService maps sync_uuid to the remote
      // `id` and never sends synced_at (matches tdee_estimates/0014's
      // exclusion premise).
      'updated_at',
      'deleted_at',
    };

    expect(
      local,
      containsAll(<String>[
        'id',
        'program_id',
        'brief_json',
        'source',
        'knowledge_version',
        'model_version',
        'confirmed_at',
        'active',
      ]),
    );
    expect(local, isNot(contains('sync_uuid')));

    // Confirm the exclusion premise against the mixin and the reference SQL
    // file (same premise tdee_estimates' own parity test confirms against
    // 0014 — reused verbatim here rather than tdee_estimates' own migration,
    // whose header prose mentions "sync_uuid" in explanatory text and would
    // produce a false-positive `contains` match).
    expect(tables, contains('mixin SyncColumns'));
    final jointPain = File(
      'supabase/migrations/0014_joint_pain_logs.sql',
    ).readAsStringSync();
    expect(jointPain, isNot(contains('sync_uuid')));
    expect(jointPain, isNot(contains('synced_at')));

    for (final column in local) {
      expect(
        RegExp('\\b$column\\b').hasMatch(sql),
        isTrue,
        reason:
            'remote herculex_ai_program_briefs is missing local column '
            '"$column"',
      );
    }
  });
}
