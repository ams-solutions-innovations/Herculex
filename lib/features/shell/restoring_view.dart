import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Shown on the web between sign-in and the first completed cloud pull.
///
/// A fresh browser database is empty; letting the app run before the pull
/// finishes would show an empty account and let startup writers (bodyweight
/// from the profile, schedule repair, TDEE recalibration) create rows that
/// duplicate what is about to arrive. The router moves on by itself once
/// `initialSyncReadyProvider` flips.
class RestoringView extends ConsumerWidget {
  const RestoringView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final sync = ref.watch(syncStateProvider).valueOrNull;
    final failed = sync?.phase == SyncPhase.error;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(HxSpace.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/app_icon_foreground.png',
                  height: 96,
                  color: hx.primary,
                ),
                const SizedBox(height: HxSpace.x8),
                Text(
                  failed ? 'Couldn’t restore your data' : 'Restoring your data',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: HxSpace.x2),
                Text(
                  failed
                      ? (sync?.lastError ?? 'Check your connection and retry.')
                      : 'Bringing your workouts, meals and programs into this '
                            'browser. This happens once per browser.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: HxSpace.x6),
                if (failed)
                  PremiumButton(
                    text: 'Retry',
                    icon: Icons.refresh_rounded,
                    onTap: () => ref.read(syncServiceProvider).retryAll(),
                  )
                else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
