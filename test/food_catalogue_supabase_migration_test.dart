import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-level guard on the shared food_catalogue migration (web track W4).
///
/// The table is shared reference data, so the properties that matter are the
/// opposite of a synced table's: signed-in users read it, nobody writes it
/// from a client, and the search function is not open to anonymous callers.
void main() {
  const path = 'supabase/migrations/20261027120000_food_catalogue.sql';

  String readSql() {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    return file.readAsStringSync().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  test('keys rows by the catalogue id food entries already reference', () {
    final sql = readSql();
    expect(sql, contains('create table food_catalogue'));
    expect(sql, contains('catalogue_id text primary key'));
    // The raw source item, so clients map it with FoodCatalogueImporter.
    expect(sql, contains('item jsonb not null'));
    // Shared data: no per-user ownership column.
    expect(sql, isNot(contains('user_id')));
  });

  test('is read-only for clients', () {
    final sql = readSql();
    expect(
      sql,
      contains('alter table food_catalogue enable row level security'),
    );
    expect(
      sql,
      contains('on food_catalogue for select to authenticated using (true)'),
    );
    for (final op in const ['insert', 'update', 'delete']) {
      expect(
        sql,
        isNot(contains('on food_catalogue for $op')),
        reason: 'no client may $op catalogue rows',
      );
    }
  });

  test('search is indexed and limited to signed-in callers', () {
    final sql = readSql();
    expect(sql, contains('using gin (name gin_trgm_ops)'));
    expect(sql, contains('create or replace function search_food_catalogue'));
    expect(sql, contains('security invoker'));
    expect(
      sql,
      contains(
        'revoke execute on function search_food_catalogue(text, int) from public',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function search_food_catalogue(text, int) to authenticated',
      ),
    );
    // Results are capped server-side whatever the client asks for.
    expect(sql, contains('least(greatest(coalesce(max_results, 20), 1), 50)'));
  });

  test('stays out of realtime and the sync tombstone machinery', () {
    final sql = readSql();
    expect(sql, isNot(contains('supabase_realtime')));
    expect(sql, isNot(contains('record_sync_tombstone')));
  });
}
