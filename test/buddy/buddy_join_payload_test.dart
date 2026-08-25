import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/domain/buddy_join_payload.dart';

void main() {
  const sampleToken = 'c1b4e2f3-1234-4567-89ab-cdef01234567';

  test('encode then tryDecode round-trips correctly', () {
    const payload = BuddyJoinPayload(sampleToken);
    final encoded = payload.encode();

    expect(encoded, 'herculex://buddy/join?t=$sampleToken');
    final decoded = BuddyJoinPayload.tryDecode(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.token, sampleToken);
    expect(decoded, equals(payload));
  });

  test('tryDecode returns null for empty, plain uuid, wrong scheme, or missing token', () {
    expect(BuddyJoinPayload.tryDecode(''), isNull);
    expect(BuddyJoinPayload.tryDecode('   '), isNull);
    expect(BuddyJoinPayload.tryDecode(sampleToken), isNull);
    expect(BuddyJoinPayload.tryDecode('https://herculex.app/buddy/join?t=$sampleToken'), isNull);
    expect(BuddyJoinPayload.tryDecode('herculex://other/join?t=$sampleToken'), isNull);
    expect(BuddyJoinPayload.tryDecode('herculex://buddy/wrong?t=$sampleToken'), isNull);
    expect(BuddyJoinPayload.tryDecode('herculex://buddy/join'), isNull);
    expect(BuddyJoinPayload.tryDecode('herculex://buddy/join?t='), isNull);
  });

  test('tryDecode handles fuzz strings without throwing', () {
    final fuzzStrings = [
      'null',
      'undefined',
      '{}',
      '[]',
      'herculex://',
      'herculex://buddy',
      'herculex://buddy/join?',
      'herculex://buddy/join?t=%zz',
      'herculex://buddy/join?t=😀🔥',
      '::not a uri::',
      'http:///malformed-uri',
      'herculex://buddy/join?t=${'a' * 10000}',
      '   herculex://buddy/join?t=valid-token   ',
      '\x00\x01\x02\x03\x04\x05',
      'herculex://buddy/join?t=&other=123',
      'herculex://buddy/join?t=token&userId=123',
      'javascript:alert(1)',
      'data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==',
      'file:///path/to/something',
      'custom://buddy/join?t=$sampleToken',
    ];

    for (final fuzz in fuzzStrings) {
      expect(() => BuddyJoinPayload.tryDecode(fuzz), returnsNormally);
    }

    final validWithSpaces = BuddyJoinPayload.tryDecode('   herculex://buddy/join?t=$sampleToken   ');
    expect(validWithSpaces, isNotNull);
    expect(validWithSpaces!.token, sampleToken);
  });
}
