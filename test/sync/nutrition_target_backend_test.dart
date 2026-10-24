import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/sync/supabase_sync_backend_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'nutrition upserts use the shared user/scope/start key across device IDs',
    () async {
      final stored = <String, Map<String, dynamic>>{};
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(
            request.url.queryParameters['on_conflict'],
            'user_id,applies_to,effective_from_date_iso',
          );
          final row = jsonDecode(request.body) as Map<String, dynamic>;
          final key =
              '${row['user_id']}/${row['applies_to']}/${row['effective_from_date_iso']}';
          stored[key] = row;
          return http.Response(
            '[]',
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final backend = SupabaseSyncBackendService(client);
      for (final device in ['a', 'b']) {
        await backend.upsert('nutrition_targets', {
          'id': device,
          'user_id': 'user-1',
          'applies_to': 'global',
          'effective_from_date_iso': '2026-10-22',
          'kcal': device == 'a' ? 2400 : 2500,
        });
      }
      expect(stored, hasLength(1));
      expect(stored.values.single['id'], 'b');
      expect(stored.values.single['kcal'], 2500);
    },
  );
}
