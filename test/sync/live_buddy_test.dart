@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/features/buddy/data/buddy_remote_gateway.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// The live server-side smoke suite for the 0011 buddy surface — everything
/// `test/buddy/*` cannot prove, because it runs against fakes. RLS is
/// enforced server-side and cannot be faked; a single-use token, an
/// existence-oracle-free rejection message, and "a departed participant
/// cannot write" are all properties of the live Postgres functions, not of
/// this app's Dart.
///
/// Follows `live_round_trip_test.dart`'s structure: a bare [SupabaseClient]
/// per device is pure Dart (http + websocket, no isolate, no plugin
/// channel), so this runs under plain `flutter test`. `Supabase.initialize()`
/// is never called.
///
/// Every test here needs two distinct accounts — RLS keys off
/// `auth.uid()`, so there is no synthetic second owner to test against —
/// unlike `live_round_trip_test.dart`, where only its one cross-user test
/// needs the second account, all five tests below do.
///
/// Run it with:
///
/// ```
/// flutter test test/sync/live_buddy_test.dart --dart-define-from-file=.secrets/live_sync.json
/// ```
const _email = String.fromEnvironment('SUPABASE_TEST_EMAIL');
const _password = String.fromEnvironment('SUPABASE_TEST_PASSWORD');
const _email2 = String.fromEnvironment('SUPABASE_TEST_EMAIL_2');
const _password2 = String.fromEnvironment('SUPABASE_TEST_PASSWORD_2');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // See live_round_trip_test.dart's identical line: flutter_test's
  // HttpOverrides fails every real request with a fake 400 unless cleared.
  HttpOverrides.global = null;

  final skipReason =
      (!Env.hasSupabase ||
          _email.isEmpty ||
          _password.isEmpty ||
          _email2.isEmpty ||
          _password2.isEmpty)
      ? 'Live Supabase buddy smoke suite. Every test needs two distinct '
            'accounts — provide SUPABASE_URL, SUPABASE_ANON_KEY, '
            'SUPABASE_TEST_EMAIL/_PASSWORD and SUPABASE_TEST_EMAIL_2/'
            '_PASSWORD_2 via --dart-define-from-file to run it.'
      : null;

  group('live buddy smoke suite', () {
    late SupabaseClient clientA;
    late SupabaseClient clientB;
    late String uidA;
    late String uidB;
    late SupabaseBuddyGateway gatewayA;
    late SupabaseBuddyGateway gatewayB;

    // Sessions this run created, so tearDown can leave them rather than
    // accumulate live rows across repeated runs. Recorded rather than
    // assumed, since a test that fails after creating a session must still
    // clean it up.
    final createdSessionIds = <String>[];

    Future<SupabaseClient> signIn(String email, String password) async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabaseAnonKey,
        // No background refresh ticker to outlive the test.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw StateError('Sign-in returned no user for $email');
      }
      return client;
    }

    setUpAll(() async {
      clientA = await signIn(_email, _password);
      clientB = await signIn(_email2, _password2);
      uidA = clientA.auth.currentUser!.id;
      uidB = clientB.auth.currentUser!.id;
      gatewayA = SupabaseBuddyGateway(client: clientA);
      gatewayB = SupabaseBuddyGateway(client: clientB);
    });

    tearDownAll(() async {
      // The only client-writable field on buddy_participants is your own
      // left_at (buddy_participants_update_self) — there is no RLS policy
      // or RPC that lets a client set buddy_sessions.ended_at, so this is
      // the actual available cleanup, not a shortcut. A session left this
      // way stays selectable by its participants but can no longer be
      // joined once its 10-minute token expires, and every write to it
      // still runs through buddy_append_event()'s own participation check.
      for (final id in createdSessionIds) {
        for (final (client, uid) in [(clientA, uidA), (clientB, uidB)]) {
          try {
            await client
                .from('buddy_participants')
                .update({'left_at': DateTime.now().toUtc().toIso8601String()})
                .eq('buddy_session_id', id)
                .eq('user_id', uid);
          } catch (e) {
            printOnFailure('cleanup of buddy session $id for $uid failed: $e');
          }
        }
      }
      await clientA.dispose();
      await clientB.dispose();
    });

    test('create and join round trip', () async {
      final created = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(created.buddySessionId);

      expect(created.buddySessionId, isNotEmpty);
      expect(created.joinToken, isNotEmpty);

      final joinedSessionId = await gatewayB.joinSession(
        token: created.joinToken,
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test B',
      );
      expect(joinedSessionId, created.buddySessionId);

      final participantsAsA = await clientA
          .from('buddy_participants')
          .select()
          .eq('buddy_session_id', created.buddySessionId);
      final participantsAsB = await clientB
          .from('buddy_participants')
          .select()
          .eq('buddy_session_id', created.buddySessionId);
      expect(participantsAsA, hasLength(2));
      expect(participantsAsB, hasLength(2));
    });

    test('token is single use', () async {
      final created = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(created.buddySessionId);

      await gatewayB.joinSession(
        token: created.joinToken,
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test B',
      );

      // The second redemption of the same token, by anyone, must fail —
      // tested here with A retrying its own token rather than a third
      // account, since the failure is about the token's consumed_at, not
      // about who is asking.
      await expectLater(
        gatewayA.joinSession(
          token: created.joinToken,
          workoutSessionUuid: const Uuid().v4(),
          displayName: 'Live Test A retry',
        ),
        throwsA(isA<BuddyJoinRejected>()),
      );
    });

    test('token gates', () async {
      // Three independent causes of rejection, asserted to produce the
      // *same* message — the existence-oracle check. Asserting each merely
      // throws would miss a later "friendlier error" refactor that leaks
      // which cause applied.
      Future<String> messageFor(Future<void> Function() attempt) async {
        try {
          await attempt();
          fail('expected a BuddyJoinRejected');
        } on BuddyJoinRejected catch (e) {
          return e.message;
        }
      }

      // Cause 1: a token that was never issued.
      final unknownMessage = await messageFor(
        () => gatewayB.joinSession(
          token: const Uuid().v4(),
          workoutSessionUuid: const Uuid().v4(),
        ),
      );

      // Cause 2: a token whose session has already been consumed once
      // (reusing "token is single use"'s scenario rather than "ended", since
      // no client-reachable path sets buddy_sessions.ended_at at all — see
      // the tearDownAll comment above).
      final consumedTokenSession = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(consumedTokenSession.buddySessionId);
      await gatewayB.joinSession(
        token: consumedTokenSession.joinToken,
        workoutSessionUuid: const Uuid().v4(),
      );
      final consumedMessage = await messageFor(
        () => gatewayA.joinSession(
          token: consumedTokenSession.joinToken,
          workoutSessionUuid: const Uuid().v4(),
        ),
      );

      // Cause 3: the host redeeming its own still-fresh token.
      final ownTokenSession = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(ownTokenSession.buddySessionId);
      final ownTokenMessage = await messageFor(
        () => gatewayA.joinSession(
          token: ownTokenSession.joinToken,
          workoutSessionUuid: const Uuid().v4(),
        ),
      );

      expect(unknownMessage, consumedMessage);
      expect(consumedMessage, ownTokenMessage);
    });

    test('join tokens are invisible', () async {
      final created = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(created.buddySessionId);

      // buddy_join_tokens has RLS enabled with zero policies AND
      // `revoke all` from anon/authenticated — deny-all by both mechanisms
      // at once, so the server response here is a thrown PostgrestException
      // (permission denied), not an empty result set. Asserted explicitly,
      // per the plan, rather than accepting either silently.
      await expectLater(
        clientA.from('buddy_join_tokens').select(),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        clientB.from('buddy_join_tokens').select(),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a departed participant cannot write', () async {
      final created = await gatewayA.createSession(
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test A',
      );
      createdSessionIds.add(created.buddySessionId);
      await gatewayB.joinSession(
        token: created.joinToken,
        workoutSessionUuid: const Uuid().v4(),
        displayName: 'Live Test B',
      );

      // The one client-writable field on buddy_participants: B leaves.
      await clientB
          .from('buddy_participants')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('buddy_session_id', created.buddySessionId)
          .eq('user_id', uidB);

      await expectLater(
        gatewayB.append(
          buddySessionId: created.buddySessionId,
          kind: BuddyEventKind.add,
          payload: const {'probe': true},
        ),
        throwsA(isA<PostgrestException>()),
      );

      // BUD-06's actual requirement: the other participant's workout
      // continues. Asserting only B's failure above would miss this half.
      final seq = await gatewayA.append(
        buddySessionId: created.buddySessionId,
        kind: BuddyEventKind.add,
        payload: const {'probe': true},
      );
      expect(seq, isNonNegative);
    });

    // Left for a later plan, per 11-05-PLAN.md Task 2: broadcast-delivery
    // (a live realtime round trip between two subscribed clients),
    // gapless-seq under concurrent appends, and a cross-user negative test
    // against buddy_sessions_local / workout_sessions (the tables this
    // migration does not touch, proving BUD-02's isolation holds at the
    // schema boundary too, not just inside buddy_* itself).
  }, skip: skipReason);
}
