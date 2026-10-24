import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('check-in serializes all current poses in one request', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['kind'], 'physique_checkin');
        expect((body['currentImages'] as List).map((p) => p['pose']), [
          'front',
          'side',
          'back',
        ]);
        expect(body['baselineImages'], hasLength(1));
        return http.Response(
          jsonEncode({
            'result': {'confidence': 'medium'},
            'provenance': {'modelVersion': 'test'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await SupabaseGeminiBackend(client).analyzePhysiqueCheckIn(
      baselineImages: [
        {
          'bytes': [1, 2],
          'mimeType': 'image/jpeg',
          'pose': 'front',
        },
      ],
      currentImages: [
        for (final pose in ['front', 'side', 'back'])
          {
            'bytes': [3, 4],
            'mimeType': 'image/jpeg',
            'pose': pose,
          },
      ],
      context: {},
    );
    expect(result.$1['confidence'], 'medium');
    expect(calls, 1);
  });

  for (final entry in [
    (429, 'quota', AiFailureKind.quota),
    (503, 'unavailable', AiFailureKind.unavailable),
    (504, 'timeout', AiFailureKind.timeout),
    (500, 'configuration', AiFailureKind.configuration),
  ]) {
    test('structured ${entry.$2} survives the function boundary', () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': 'Please try later',
              'code': entry.$2,
              'retryable': entry.$1 >= 500,
              'requestId': 'trace-1',
            }),
            entry.$1,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseGeminiBackend(
          client,
        ).analyzeFoodPhoto(imageBytes: [1], mimeType: 'image/jpeg'),
        throwsA(
          isA<AiBackendException>().having((e) => e.kind, 'kind', entry.$3),
        ),
      );
      expect(
        calls,
        1,
        reason: 'The client must not retry an already processed AI request.',
      );
    });
  }

  test('network failures are actionable typed failures', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((_) async {
        throw const SocketException('offline');
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseGeminiBackend(
        client,
      ).analyzeFoodPhoto(imageBytes: [1], mimeType: 'image/jpeg'),
      throwsA(
        isA<AiBackendException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.unavailable,
        ),
      ),
    );
  });
}
