import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/buddy/application/buddy_session_controller.dart';
import 'package:herculex/features/buddy/presentation/buddy_share_sheet.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  testWidgets(
    'BuddyShareSheet renders QR when waiting for partner and hides raw token',
    (tester) async {
      const rawToken = 'secret-join-token-12345';
      final controller = SettableBuddyController(
        db: db,
        gateway: gateway,
        channelService: channelService,
        workouts: workouts,
        resolver: resolver,
        currentUserId: 'user-1',
        initialState: const BuddySessionState(
          buddySessionId: 'sess-1',
          pendingJoinToken: rawToken,
          isHost: true,
          isLive: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            buddySessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: Scaffold(body: BuddyShareSheet())),
        ),
      );

      // QrImageView is present
      expect(find.byType(QrImageView), findsOneWidget);

      // Raw token is NEVER rendered as a Text widget
      expect(find.text(rawToken), findsNothing);
      expect(find.textContaining('secret-join-token'), findsNothing);

      // Cancel invite button is visible
      expect(find.text('Cancel Invite'), findsOneWidget);
    },
  );

  testWidgets(
    'BuddyShareSheet replaces QR with partner info once partner joins',
    (tester) async {
      final controller = SettableBuddyController(
        db: db,
        gateway: gateway,
        channelService: channelService,
        workouts: workouts,
        resolver: resolver,
        currentUserId: 'user-1',
        initialState: const BuddySessionState(
          buddySessionId: 'sess-1',
          partner: BuddyParticipant(
            userId: 'user-partner',
            displayName: 'Alex Partner',
          ),
          isHost: true,
          isLive: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            buddySessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: Scaffold(body: BuddyShareSheet())),
        ),
      );

      // QR image is removed from the widget tree
      expect(find.byType(QrImageView), findsNothing);

      // Partner info is rendered
      expect(find.text('Alex Partner'), findsOneWidget);
      expect(find.text('Training together now'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('End Shared Session'), findsOneWidget);
    },
  );
}
