import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/features/profile/presentation/profile_view.dart';

/// The badge is the entire user-facing surface of RB-02 — the blocker was
/// filed because the old `SyncEngine` rendered "synced" off an empty outbox
/// it had never tried to drain. `SyncService` now derives a real [SyncState],
/// but nothing checked that the widget renders it faithfully; the phase→label
/// mapping was guaranteed only by the `switch` being exhaustive, which says
/// nothing about whether the strings are right.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, SyncState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncStateProvider.overrideWith((ref) => Stream.value(state)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: SyncStatusBadge())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const cases = <(SyncState, String, IconData)>[
    (
      SyncState(phase: SyncPhase.disabled),
      'Cloud sync off',
      Icons.cloud_off_outlined,
    ),
    // Note the ellipsis is U+2026, not three periods.
    (SyncState(phase: SyncPhase.syncing), 'Syncing…', Icons.cloud_sync_outlined),
    (
      SyncState(phase: SyncPhase.pending, pendingCount: 3),
      '3 pending',
      Icons.cloud_upload_outlined,
    ),
    (SyncState(phase: SyncPhase.synced), 'Synced', Icons.cloud_done_outlined),
    (
      SyncState(phase: SyncPhase.error, lastError: 'boom'),
      'Sync error',
      Icons.cloud_off,
    ),
  ];

  for (final (state, label, icon) in cases) {
    testWidgets('renders "$label" for ${state.phase.name}', (tester) async {
      await pump(tester, state);
      expect(find.text(label), findsOneWidget);
      expect(find.byIcon(icon), findsOneWidget);
    });
  }

  testWidgets('never claims "Synced" for any phase that is not synced',
      (tester) async {
    for (final (state, _, _) in cases) {
      if (state.phase == SyncPhase.synced) continue;
      await pump(tester, state);
      expect(
        find.text('Synced'),
        findsNothing,
        reason: '${state.phase.name} must not read as success — this is the '
            'exact failure RB-02 was filed for',
      );
    }
  });

  testWidgets('falls back to disabled before the stream has produced a state',
      (tester) async {
    // A pending `AsyncValue` has no value. The badge must not guess
    // optimistically while sync is still starting up.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncStateProvider.overrideWith((ref) => const Stream<SyncState>.empty()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: SyncStatusBadge())),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Cloud sync off'), findsOneWidget);
  });

  testWidgets('surfaces the underlying error in the tooltip', (tester) async {
    await pump(
      tester,
      const SyncState(phase: SyncPhase.error, lastError: 'quarantined: 403'),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'quarantined: 403');
  });

  testWidgets('an error with no detail still explains itself', (tester) async {
    await pump(tester, const SyncState(phase: SyncPhase.error));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Some changes could not be uploaded.');
  });

  testWidgets('a synced badge reports when it last synced', (tester) async {
    final at = DateTime(2026, 8, 12, 9, 30);
    await pump(tester, SyncState(phase: SyncPhase.synced, lastSyncedAt: at));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Last synced'));
    expect(tooltip.message, contains('2026'));
  });

  testWidgets('a never-synced badge says so rather than implying success',
      (tester) async {
    await pump(tester, const SyncState(phase: SyncPhase.pending, pendingCount: 1));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Not yet synced to the cloud.');
  });
}
