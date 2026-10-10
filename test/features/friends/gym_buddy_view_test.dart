import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/friends/application/friends_providers.dart';
import 'package:herculex/features/friends/data/friends_gateway.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/friends/presentation/views/friend_detail_view.dart';
import 'package:herculex/features/friends/presentation/views/gym_buddy_view.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway implements FriendsGateway {
  _FakeGateway(this.friends);

  final List<FriendEntry> friends;
  int profileUpserts = 0;
  int snapshotPublishes = 0;
  bool? lastSharing;

  @override
  Future<void> upsertProfile({
    required String? displayName,
    required String? avatarId,
    required bool sharingEnabled,
  }) async {
    profileUpserts++;
    lastSharing = sharingEnabled;
  }

  @override
  Future<void> publishSnapshot(FriendSnapshot snapshot) async =>
      snapshotPublishes++;

  @override
  Future<List<FriendEntry>> fetchFriends() async => friends;

  @override
  Future<String> createInvite() async => 'token';

  @override
  Future<String> acceptInvite(String token) async => 'friend';

  @override
  Future<void> removeFriend(String friendUserId) async {}

  @override
  Future<Map<String, DateTime>> sharedSessions(String friendUserId) async =>
      const {};
}

const _mySnapshot = FriendSnapshot(
  levelTitle: 'Intermediate III',
  completedWorkouts: 30,
  weekTonnageKg: 0,
  lifts: [FriendLift(lift: StrengthLift.squat, value: 1.5, e1rmKg: 120)],
  recentPrs: [],
  buddySessions: [],
);

const _ana = FriendEntry(
  userId: 'ana',
  displayName: 'Ana',
  snapshot: FriendSnapshot(
    levelTitle: 'Advanced I',
    completedWorkouts: 80,
    weekTonnageKg: 0,
    lifts: [FriendLift(lift: StrengthLift.squat, value: 1.9, e1rmKg: 140)],
    recentPrs: [],
    buddySessions: [],
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool available,
  required _FakeGateway gateway,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      friendsGatewayProvider.overrideWithValue(gateway),
      friendsAvailableProvider.overrideWithValue(available),
      myFriendSnapshotProvider.overrideWith((ref) async => _mySnapshot),
      profileProvider.overrideWith((ref) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GymBuddyView()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('signed out: asks to sign in, no friends query', (tester) async {
    final gateway = _FakeGateway(const [_ana]);
    await _pump(tester, available: false, gateway: gateway);
    expect(find.text('Sign in to use Gym Buddy'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('lists friends and ranks main lifts with the user', (
    tester,
  ) async {
    await _pump(tester, available: true, gateway: _FakeGateway(const [_ana]));
    expect(find.text('Main lifts'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    // Ana appears in the leaderboard and in the friends list.
    expect(find.text('Ana'), findsNWidgets(2));
    expect(find.text('Advanced I'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
  });

  testWidgets('no friends yet shows the invite prompt', (tester) async {
    await _pump(tester, available: true, gateway: _FakeGateway(const []));
    expect(find.text('No gym buddies yet'), findsOneWidget);
    expect(find.text('Add a friend'), findsOneWidget);
  });

  testWidgets('friend page compares lifts, goal, PRs and shared sessions', (
    tester,
  ) async {
    final bor = FriendEntry(
      userId: 'bor',
      displayName: 'Bor',
      snapshot: FriendSnapshot(
        levelTitle: 'Elite I',
        completedWorkouts: 200,
        weekTonnageKg: 0,
        lifts: const [
          FriendLift(lift: StrengthLift.squat, value: 2.3, e1rmKg: 190),
        ],
        recentPrs: [
          FriendPr(exercise: 'Deadlift', e1rmKg: 250, at: DateTime(2026, 10)),
        ],
        buddySessions: [
          FriendBuddySession(
            buddySessionId: 'b1',
            at: DateTime(2026, 9, 28),
            tonnageKg: 9000,
            sets: 20,
          ),
        ],
        goal: const FriendGoal(startKg: 80, currentKg: 85, targetKg: 90),
      ),
    );
    final gateway = _FakeGateway([bor]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          friendsGatewayProvider.overrideWithValue(gateway),
          friendsAvailableProvider.overrideWithValue(true),
          myFriendSnapshotProvider.overrideWith((ref) async => _mySnapshot),
          profileProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: FriendDetailView(friendId: 'bor')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VS'), findsOneWidget);
    expect(find.text('Main lifts'), findsOneWidget);
    expect(find.text('190 kg'), findsOneWidget);
    expect(find.text('120 kg'), findsOneWidget);
    expect(find.text('Closest to the goal'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text("Bor's recent PRs"), findsOneWidget);
    expect(find.text('Trained together'), findsOneWidget);
    // Only Bor's snapshot has b1, so it is not a shared session.
    expect(find.textContaining('Them: 9.0 t'), findsNothing);
  });

  group('FriendSnapshotPublisher', () {
    testWidgets('does nothing while signed out', (tester) async {
      final gateway = _FakeGateway(const []);
      final c = await _pump(tester, available: false, gateway: gateway);
      await c.read(friendSnapshotPublisherProvider).publishNow();
      expect(gateway.profileUpserts, 0);
      expect(gateway.snapshotPublishes, 0);
    });

    testWidgets('sharing off updates the flag but never the stats', (
      tester,
    ) async {
      final gateway = _FakeGateway(const []);
      final c = await _pump(tester, available: true, gateway: gateway);
      await c.read(friendSharingProvider.notifier).set(false);
      expect(gateway.lastSharing, isFalse);
      expect(gateway.snapshotPublishes, 0);

      await c.read(friendSharingProvider.notifier).set(true);
      expect(gateway.lastSharing, isTrue);
      expect(gateway.snapshotPublishes, 1);
    });
  });
}
