import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the weekly_reports migration (schema chore 5).
///
/// A column that exists locally but not in Postgres makes PostgREST answer
/// PGRST204 and the outbox quarantines the row after 8 attempts, which looks
/// fine locally. The parity test derives the expected column list from the
/// drift definition so the two cannot drift apart silently.
void main() {
  const path = 'supabase/migrations/20261003000000_weekly_reports_v48.sql';

  String readSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    // Collapse whitespace so assertions do not depend on line wrapping.
    return file.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  /// The SQL with every `--` comment removed. Comments are stripped PER LINE
  /// on the raw text (collapsing newlines first would make a trailing comment
  /// swallow the rest of the file), then the result is lowercased and
  /// whitespace-collapsed. The header legitimately says "NO unique
  /// constraint", so negative assertions must not see it.
  String readExecutableSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    final stripped = file
        .readAsStringSync()
        .split('\n')
        .map((line) {
          final i = line.indexOf('--');
          return i < 0 ? line : line.substring(0, i);
        })
        .join('\n')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(stripped, contains('create table weekly_reports'));
    return stripped;
  }

  test('creates weekly_reports with the exact column definitions', () {
    final sql = readSql();
    expect(sql, contains('create table weekly_reports'));
    for (final column in const [
      'id uuid primary key',
      'user_id uuid not null references auth.users(id) on delete cascade',
      'iso_year integer not null',
      'iso_week integer not null',
      'week_start_iso text not null',
      'generated_at timestamptz not null default now()',
      'payload_version integer not null default 1',
      'payload_json text not null',
      'narrative_json text,',
      'narrative_attempts integer not null default 0',
      'knowledge_version text,',
      'model_version text,',
      'tdee_decision text,',
      'tdee_decision_kcal integer,',
      'viewed_at timestamptz,',
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
      contains('alter table weekly_reports enable row level security'),
    );
    for (final op in const ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('weekly_reports_${op}_own'));
    }
    expect(
      sql,
      contains(
        'on weekly_reports for insert with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains(
        'on weekly_reports for update using (user_id = auth.uid()) '
        'with check (user_id = auth.uid())',
      ),
    );
    expect(
      sql,
      contains('on weekly_reports for select using (user_id = auth.uid())'),
    );
    expect(
      sql,
      contains('on weekly_reports for delete using (user_id = auth.uid())'),
    );
    final executable = readExecutableSql();
    expect('create policy'.allMatches(executable).length, 4);
  });

  test('wires triggers, realtime publication and the pull index', () {
    final sql = readSql();
    expect(sql, contains('t_set_updated_at_weekly_reports'));
    expect(sql, contains('execute function set_updated_at()'));
    expect(sql, contains('t_record_tombstone_weekly_reports'));
    expect(sql, contains('execute function public.record_sync_tombstone()'));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.weekly_reports',
      ),
    );
    expect(
      sql,
      contains(
        'create index if not exists weekly_reports_user_updated_idx '
        'on public.weekly_reports (user_id, updated_at, id)',
      ),
    );
  });

  test('has no column constraints and no unique on (iso_year, iso_week)', () {
    final sql = readExecutableSql();
    // Only RLS `with check (...)` clauses are allowed; no column constraint.
    expect(RegExp(r'(?<!with )check\s*\(').hasMatch(sql), isFalse);
    expect(sql, isNot(contains('constraint')));
    // One row per week is enforced locally; a remote unique would turn a
    // second device's push into 23505 (RESEARCH Pitfall 5).
    expect(sql, isNot(contains('unique')));
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
      r'class WeeklyReports extends Table[^{]*\{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(tables);
    expect(classMatch, isNotNull, reason: 'WeeklyReports class not found');

    String snake(String camel) => camel.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );

    final local = <String>{
      for (final m in RegExp(
        r'get (\w+)\s*=>?',
      ).allMatches(classMatch!.group(1)!))
        // `uniqueKeys` is a drift override, not a column.
        if (m.group(1) != 'uniqueKeys') snake(m.group(1)!),
      // SyncColumns / SyncTombstone contributions. sync_uuid and synced_at are
      // local-only bookkeeping: SyncService maps sync_uuid to the remote `id`
      // and never sends synced_at (0014 joint_pain_logs has neither).
      'updated_at',
      'deleted_at',
    };

    expect(
      local,
      containsAll(<String>[
        'iso_year',
        'iso_week',
        'week_start_iso',
        'payload_json',
        'narrative_json',
        'viewed_at',
      ]),
    );
    expect(local, isNot(contains('sync_uuid')));
    expect(local, isNot(contains('unique_keys')));

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
        reason: 'remote weekly_reports is missing local column "$column"',
      );
    }
  });
}
