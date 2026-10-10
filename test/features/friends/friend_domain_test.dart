import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/deep_links.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_invite_payload.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';

const _token = '0b8f2a8e-3c1d-4e5f-9a7b-1c2d3e4f5a6b';

FriendSnapshot _snap({
  List<FriendLift> lifts = const [],
  List<FriendBuddySession> buddy = const [],
}) => FriendSnapshot(
  levelTitle: 'Advanced II',
  completedWorkouts: 42,
  weekTonnageKg: 12000,
  lifts: lifts,
  recentPrs: const [],
  buddySessions: buddy,
);

FriendEntry _person(String name, FriendSnapshot? s, {bool me = false}) =>
    FriendEntry(userId: name, displayName: name, snapshot: s, isMe: me);

void main() {
  group('FriendInvitePayload', () {
    test('round-trips through a link', () {
      final link = const FriendInvitePayload(_token).encode();
      expect(link, 'herculex://friend/invite?t=$_token');
      expect(FriendInvitePayload.tryDecode(link)?.token, _token);
    });

    test('accepts a bare pasted code', () {
      expect(FriendInvitePayload.tryDecode('  $_token ')?.token, _token);
    });

    test('rejects other links, including buddy joins', () {
      for (final raw in [
        '',
        'hello',
        'herculex://buddy/join?t=$_token',
        'https://friend/invite?t=$_token',
        'herculex://friend/invite',
        'herculex://friend/other?t=x',
      ]) {
        expect(FriendInvitePayload.tryDecode(raw), isNull, reason: raw);
      }
    });
  });

  group('routeForDeepLink', () {
    test('friend invites open the accept screen', () {
      expect(
        routeForDeepLink(Uri.parse('herculex://friend/invite?t=$_token')),
        AppPaths.friendInvite(_token),
      );
    });

    test('the auth callback is left to supabase', () {
      expect(
        routeForDeepLink(Uri.parse('io.supabase.herculex://login-callback/')),
        isNull,
      );
    });
  });

  group('FriendSnapshot JSON', () {
    test('round-trips', () {
      final s = FriendSnapshot(
        levelTitle: 'Elite I',
        completedWorkouts: 7,
        weekTonnageKg: 8000.5,
        lifts: const [
          FriendLift(
            lift: StrengthLift.squat,
            value: 1.9,
            e1rmKg: 160,
            lifterTopPct: 14,
          ),
          FriendLift(lift: StrengthLift.pullUp, value: 12),
        ],
        recentPrs: [
          FriendPr(
            exercise: 'Bench Press',
            e1rmKg: 120,
            at: DateTime.utc(2026, 10, 1).toLocal(),
          ),
        ],
        buddySessions: [
          FriendBuddySession(
            buddySessionId: 'b1',
            at: DateTime.utc(2026, 9, 30).toLocal(),
            tonnageKg: 9000,
            sets: 18,
            topExercise: 'Deadlift',
            topKg: 200,
            topReps: 3,
          ),
        ],
        goal: const FriendGoal(startKg: 90, currentKg: 85, targetKg: 80),
      );
      final back = FriendSnapshot.fromJson(s.toJson());
      expect(back.levelTitle, 'Elite I');
      expect(back.lifts.first.e1rmKg, 160);
      expect(back.lifts.last.e1rmKg, isNull);
      expect(back.recentPrs.single.exercise, 'Bench Press');
      expect(back.recentPrs.single.at, s.recentPrs.single.at);
      expect(back.buddySessions.single.topKg, 200);
      expect(back.goal!.progress, closeTo(0.5, 1e-9));
    });

    test('drops entries it does not understand instead of throwing', () {
      final back = FriendSnapshot.fromJson({
        'v': 99,
        'lifts': [
          {'lift': 'squat', 'value': 1.5},
          {'lift': 'yoke-walk', 'value': 3},
          'garbage',
        ],
        'recentPrs': [
          {'exercise': 'X'},
        ],
        'goal': 'nope',
      });
      expect(back.lifts.single.lift, StrengthLift.squat);
      expect(back.recentPrs, isEmpty);
      expect(back.goal, isNull);
      expect(back.completedWorkouts, 0);
    });
  });

  test('FriendGoal progress works for bulks and cuts and clamps', () {
    expect(
      const FriendGoal(startKg: 70, currentKg: 75, targetKg: 80).progress,
      closeTo(0.5, 1e-9),
    );
    expect(
      const FriendGoal(startKg: 90, currentKg: 92, targetKg: 80).progress,
      0,
    );
    expect(
      const FriendGoal(startKg: 90, currentKg: 78, targetKg: 80).progress,
      1,
    );
  });

  group('FriendComparison', () {
    test('leaderboard ranks by e1RM kg, skips people without the lift', () {
      final people = [
        _person(
          'You',
          _snap(
            lifts: const [
              FriendLift(lift: StrengthLift.bench, value: 1.2, e1rmKg: 100),
            ],
          ),
          me: true,
        ),
        _person(
          'Ana',
          _snap(
            lifts: const [
              // Lower ratio, heavier bar: kg decides.
              FriendLift(lift: StrengthLift.bench, value: 1.1, e1rmKg: 110),
            ],
          ),
        ),
        _person('Bor', null),
      ];
      final rows = FriendComparison.leaderboard(StrengthLift.bench, people);
      expect(rows.map((r) => r.entry.displayName), ['Ana', 'You']);
      expect(FriendComparison.liftsWithData(people), [StrengthLift.bench]);
    });

    test('shared sessions: both sides, plus server-only ones', () {
      FriendBuddySession b(String id, int day) => FriendBuddySession(
        buddySessionId: id,
        at: DateTime(2026, 10, day),
        tonnageKg: 1000,
        sets: 10,
      );
      final mine = _snap(buddy: [b('a', 1), b('only-mine', 2)]);
      final theirs = _snap(buddy: [b('a', 1), b('only-theirs', 3)]);
      final shared = FriendComparison.sharedSessions(
        mine: mine,
        theirs: theirs,
        serverIds: {'srv': DateTime(2026, 10, 5)},
      );
      expect(shared.map((s) => s.buddySessionId), ['srv', 'a']);
      expect(shared.last.mine, isNotNull);
      expect(shared.last.theirs, isNotNull);
      expect(shared.first.mine, isNull);
    });
  });
}
