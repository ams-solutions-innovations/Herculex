import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the tdee_estimates migration (schema chore 5).
///
/// A column that exists locally but not in Postgres makes PostgREST answer
/// PGRST204 and the outbox quarantines the row after 8 attempts, which looks
/// fine locally. The parity test derives the expected column list from the
/// drift definition so the two cannot drift apart silently.
void main() {
  const path = 'supabase/migrations/20260928000000_tdee_estimates_v45.sql';

  String readSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    // Collapse whitespace so assertions do not depend on line wrapping.
    return file.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  test('creates tdee_estimates with the exact column definitions', () {
    final sql = readSql();
    expect(sql, contains('create table tdee_estimates'));
    for (final column in const [
      'id uuid primary key',
      'user_id uuid not null references auth.users(id) on delete cascade',
      'date_iso text not null',
      'estimated_at timestamptz not null default now()',
      'method text not null',
      'confidence text not null',
      'window_days integer not null',
      'kcal integer not null',
      'observed_qualified boolean not null default false',
      'inputs_json text not null',
      'updated_at timestamptz not null default now()',
      'deleted_at timestamptz',
    ]) {
      expect(sql, contains(column));
    }
  });

  test('is owner-only: RLS enabled and four user_id = auth.uid() policies', () {
    final sql = readSql();
    expect(
      sql,
      contains('alter table tdee_estimates enable row level security'),
    );
    for (final op in const ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('tdee_estimates_${op}_own'));
    }
    expect(
      sql,
      contains(
        'on tdee_estimates for insert with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains(
        'on tdee_estimates for update using (user_id = auth.uid()) '
        'with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains('on tdee_estimates for select using (user_id = auth.uid())'),
    );
    expect(
      sql,
      contains('on tdee_estimates for delete using (user_id = auth.uid())'),
    );
    expect('create policy'.allMatches(sql).length, 4);
  });

  test('wires triggers, realtime publication and the pull index', () {
    final sql = readSql();
    expect(sql, contains('t_set_updated_at_tdee_estimates'));
    expect(sql, contains('execute function set_updated_at()'));
    expect(sql, contains('t_record_tombstone_tdee_estimates'));
    expect(sql, contains('execute function public.record_sync_tombstone()'));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.tdee_estimates',
      ),
    );
    expect(
      sql,
      contains(
        'create index if not exists tdee_estimates_user_updated_idx '
        'on public.tdee_estimates (user_id, updated_at, id)',
      ),
    );
  });

  test('does not constrain method/confidence vocabulary', () {
    final sql = readSql();
    // Only RLS `with check (...)` clauses are allowed; no column constraint.
    expect(RegExp(r'(?<!with )check\s*\(').hasMatch(sql), isFalse);
    expect(sql, isNot(contains('constraint')));
  });

  test('header names the right project and the ordering requirement', () {
    final sql = readSql();
    expect(sql, contains('ldzgyzigvbwofbswitrv'));
    expect(sql, contains('0015_workout_circuits_and_session_columns'));
    expect(sql, contains('0016_exercise_progression_double'));
  });

  test('every local drift column exists remotely (snake_case parity)', () {
    final sql = readSql();
    final tables = File('lib/data/local/tables.dart').readAsStringSync();

    final classMatch = RegExp(
      r'class TdeeEstimates extends Table[^{]*\{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(tables);
    expect(classMatch, isNotNull, reason: 'TdeeEstimates class not found');

    String snake(String camel) => camel.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );

    final local = <String>{
      for (final m in RegExp(
        r'get (\w+)\s*=>?',
      ).allMatches(classMatch!.group(1)!))
        snake(m.group(1)!),
      // SyncColumns / SyncTombstone contributions. sync_uuid and synced_at are
      // local-only bookkeeping: SyncService maps sync_uuid to the remote `id`
      // and never sends synced_at (0014 joint_pain_logs has neither).
      'updated_at',
      'deleted_at',
    };

    expect(
      local,
      containsAll(<String>['date_iso', 'estimated_at', 'observed_qualified']),
    );
    expect(local, isNot(contains('sync_uuid')));

    // Confirm the exclusion premise against the mixin and the reference SQL.
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
        reason: 'remote tdee_estimates is missing local column "$column"',
      );
    }
  });
}
