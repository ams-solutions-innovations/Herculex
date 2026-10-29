import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the user_preferences migration (schema chore 5 for
/// local v53). A column that exists locally but not in Postgres makes
/// PostgREST answer PGRST204 and the outbox quarantines the row.
void main() {
  const path = 'supabase/migrations/20261027130000_user_preferences.sql';

  String readSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    return file.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  test('creates user_preferences with the synced column set', () {
    final sql = readSql();
    expect(sql, contains('create table user_preferences'));
    for (final column in const [
      'id uuid primary key',
      'user_id uuid not null references auth.users(id) on delete cascade',
      'pref_key text not null',
      'value_json text not null',
      'updated_at timestamptz not null default now()',
      'deleted_at timestamptz',
      'unique (user_id, pref_key)',
    ]) {
      expect(sql, contains(column));
    }
  });

  test('is owner-only: RLS enabled and four user_id = auth.uid() policies', () {
    final sql = readSql();
    expect(
      sql,
      contains('alter table user_preferences enable row level security'),
    );
    for (final op in const ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('user_preferences_${op}_own'));
    }
    expect(
      sql,
      contains(
        'on user_preferences for insert with check (user_id = auth.uid())',
      ),
    );
  });

  test('has the sync clock, tombstones, realtime and the pull index', () {
    final sql = readSql();
    expect(sql, contains('execute function set_updated_at()'));
    expect(sql, contains('execute function public.record_sync_tombstone()'));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.user_preferences',
      ),
    );
    expect(sql, contains('(user_id, updated_at, id)'));
  });
}
