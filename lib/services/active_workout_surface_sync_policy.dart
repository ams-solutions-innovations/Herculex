import 'package:flutter_riverpod/flutter_riverpod.dart';

bool shouldClearOngoingWorkoutSurface<T>(AsyncValue<T?> activeSession) {
  return activeSession.hasValue && activeSession.value == null;
}

/// Whether the Workout Bubble should currently be on screen.
///
/// All four conditions have to hold at once:
///
/// - there is a resolved, non-null active session,
/// - the user turned the bubble on in settings,
/// - the app is in the background (a chat head over our own UI is noise), and
/// - "Display over other apps" is granted.
///
/// A still-loading session is deliberately not treated as "no session" — same
/// rule as [shouldClearOngoingWorkoutSurface]. It just isn't treated as a
/// session either, so nothing is shown until the state resolves.
///
/// Read through `valueOrNull`, not `asData`: a provider that errors while
/// holding a previous session is still `hasValue`, and the existing surface
/// convention is to keep the surface up across a transient error rather than
/// flicker it away.
bool shouldShowWorkoutBubble<T>({
  required AsyncValue<T?> activeSession,
  required bool enabled,
  required bool appBackgrounded,
  required bool permissionGranted,
}) {
  if (!enabled || !appBackgrounded || !permissionGranted) return false;
  return activeSession.hasValue && activeSession.valueOrNull != null;
}
