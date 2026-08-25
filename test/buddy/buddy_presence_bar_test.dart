import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/buddy/application/buddy_session_controller.dart';
import 'package:herculex/features/buddy/presentation/buddy_presence_bar.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../support/test_database.dart';
import 'buddy_session_controller_test.dart';
import 'fake_buddy_gateway.dart';

class SettableBuddyController extends BuddySessionController {
  SettableBuddyController({
    required super.db,
    required super.gateway,
    required super.channelService,
    required super.workouts,
    required super.resolver,
    required super.currentUserId,
    required BuddySessionState initialState,
  }) {
    state = initialState;
  }
}

void main() {
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late FakeBuddyGateway gateway;
  late FakeBuddyChannelService channelService;

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    gateway = FakeBuddyGateway();
    channelService = FakeBuddyChannelService(gateway: gateway);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('BuddyPresenceBar renders nothing when not sharing', (tester) async {
    final controller = SettableBuddyController(
      db: db,
      gateway: gateway,
      channelService: channelService,
      workouts: workouts,
      resolver: resolver,
      currentUserId: 'user-1',
      initialState: const BuddySessionState(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          buddySessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BuddyPresenceBar(),
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.textContaining('Gym Buddy'), findsNothing);
  });

  testWidgets('BuddyPresenceBar renders partner name and notice when sharing', (tester) async {
    final controller = SettableBuddyController(
      db: db,
      gateway: gateway,
      channelService: channelService,
      workouts: workouts,
      resolver: resolver,
      currentUserId: 'user-1',
      initialState: const BuddySessionState(
        buddySessionId: 'sess-1',
        partner: BuddyParticipant(userId: 'u2', displayName: 'Sam Partner'),
        isHost: false,
        isLive: true,
        notice: 'Your partner removed Bench Press, but your logged sets were kept',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          buddySessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BuddyPresenceBar(),
          ),
        ),
      ),
    );

    expect(find.text('Training with Sam Partner'), findsOneWidget);
    expect(find.text('Your partner removed Bench Press, but your logged sets were kept'), findsOneWidget);
  });
}
