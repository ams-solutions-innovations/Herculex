import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/features/health/application/health_providers.dart';

/// How stale the last sync may get before a resume or tick triggers a new one.
const healthAutoSyncMinInterval = Duration(minutes: 15);

/// How often to re-sync while the app stays in the foreground.
const healthAutoSyncPeriod = Duration(minutes: 20);

/// Keeps Health Connect / HealthKit data fresh without the manual "Sync now".
///
/// Syncs on app open, on every foreground resume and every
/// [healthAutoSyncPeriod] while the app is open, throttled to
/// [healthAutoSyncMinInterval]. It never asks for permissions — if the user has
/// not granted them it does nothing. There is no background scheduler in this
/// project, so nothing runs while the app is closed. Registered from `app.dart`.
final healthAutoSyncProvider = Provider<void>((ref) {
  final caps = ref.watch(platformCapabilitiesProvider);
  if (!caps.hasHealthPlatform) return;

  final clock = ref.watch(clockProvider);
  var running = false;

  Future<void> sync({bool force = false}) async {
    if (running) return;
    final enabled =
        ref.read(googleHealthAutoSyncProvider) ||
        ref.read(appleHealthAutoSyncProvider) ||
        ref.read(samsungHealthAutoSync3xProvider);
    if (!enabled) return;

    final last = ref.read(lastHealthSyncTimestampProvider);
    if (!force &&
        last != null &&
        clock.now().difference(last) < healthAutoSyncMinInterval) {
      return;
    }

    running = true;
    try {
      final service = ref.read(healthServiceProvider);
      if (!await service.checkHasPermissions()) return;
      final result = await service.runDailySync();
      ref.read(lastDailyHealthReadProvider.notifier).state = result;
      ref.read(lastHealthSyncTimestampProvider.notifier).state = clock.now();
    } catch (_) {
      // Best effort: the manual sync button still reports errors.
    } finally {
      running = false;
    }
  }

  final observer = _ResumeObserver(() => unawaited(sync()));
  WidgetsBinding.instance.addObserver(observer);
  final timer = Timer.periodic(healthAutoSyncPeriod, (_) => unawaited(sync()));
  ref.onDispose(() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(observer);
  });

  unawaited(sync());
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
