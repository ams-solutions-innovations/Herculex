import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/data/buddy_channel_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_buddy_gateway.dart';

void main() {
  late SupabaseClient client;
  late FakeBuddyGateway gateway;
  late BuddyChannelService service;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'fake-anon-key');
    gateway = FakeBuddyGateway();
    service = BuddyChannelService(client: client, gateway: gateway);
  });

  tearDown(() {
    service.dispose();
  });

  test('disconnect before connect is a safe no-op', () async {
    expect(() => service.disconnect(), returnsNormally);
  });

  test('connect without an active auth session throws StateError', () async {
    expect(
      () => service.connect(
        buddySessionId: 'session-123',
        lastSeenSeq: 0,
        userId: 'user-1',
        apply: (_) async {},
        commitSeq: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('service disposes cleanly', () {
    expect(() => service.dispose(), returnsNormally);
  });
}
