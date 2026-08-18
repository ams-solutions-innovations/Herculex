import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUD-05: `supabase/migrations/0003_sync_rls.sql` is frozen. Row-level
/// security is the last line of defense against one buddy reading or
/// writing another user's rows through the shared broadcast channel — see
/// `11-RESEARCH.md` § Pitfall 5. If this policy genuinely needs to change,
/// that is a new phase decision, not a hash bump in this test.
void main() {
  test('0003_sync_rls.sql is byte-for-byte frozen', () {
    final file = File('supabase/migrations/0003_sync_rls.sql');

    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Expected supabase/migrations/0003_sync_rls.sql to exist — run '
          'from repo root. BUD-05 pins this file; it must not be able to '
          'pass vacuously against a missing file.',
    );

    final bytes = file.readAsBytesSync();
    expect(
      bytes.length,
      greaterThan(1000),
      reason:
          'supabase/migrations/0003_sync_rls.sql is suspiciously small — '
          'BUD-05 refuses to hash a near-empty file, which would let the '
          'gate pass vacuously.',
    );

    // Normalise CRLF to LF before hashing so the pin is stable regardless of
    // a checkout's line-ending settings.
    final normalised = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0D && i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
        continue;
      }
      normalised.add(bytes[i]);
    }

    final digest = sha256.convert(normalised).toString();
    expect(
      digest,
      'f50be2f89c775245e2700c2e532065c7d89ea240da0ef5ed77ff14bb25697530',
      reason:
          'BUD-05 freezes supabase/migrations/0003_sync_rls.sql — every '
          'synced table must stay gated by "user_id = auth.uid()" on select, '
          'insert, update and delete. If a policy genuinely must change, '
          'that is a new phase decision, not a hash bump in this test.',
    );
  });
}
