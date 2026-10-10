import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';

/// A [BuildContext] that can open sheets, dialogs and routes, once the app
/// shell is on screen. Null if it never gets there within [timeout].
///
/// `_HerculexAppState.context` can't: that State builds the `MaterialApp`, so
/// its context sits above the root `Navigator`, and `showModalBottomSheet` /
/// `Navigator.push` throw "context that does not include a Navigator". Home-
/// screen widget taps arrive on that State, so they come here for a context.
///
/// Call `router.go(AppRoutes.app)` first. On a cold start the tap is collected
/// after the first frame, while the router is still on the splash screen
/// waiting for the profile; a sheet shown then would sit over the splash and
/// be buried by the redirect. This waits until the shell is the location.
Future<BuildContext?> awaitShellContext(
  GoRouter router, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  const poll = Duration(milliseconds: 50);
  // Counted rather than timed, so it behaves the same under a fake clock.
  final attempts = timeout.inMilliseconds ~/ poll.inMilliseconds;
  final delegate = router.routerDelegate;
  for (var i = 0; i < attempts; i++) {
    final navigator = delegate.navigatorKey.currentContext;
    final onShell = delegate.currentConfiguration.uri.path == AppRoutes.app;
    if (onShell && navigator != null && navigator.mounted) {
      // The location flips before the page is built; let that frame finish.
      await WidgetsBinding.instance.endOfFrame;
      return navigator.mounted ? navigator : null;
    }
    await Future<void>.delayed(poll);
  }
  return null;
}
