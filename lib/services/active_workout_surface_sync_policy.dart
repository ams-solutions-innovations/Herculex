import 'package:flutter_riverpod/flutter_riverpod.dart';

bool shouldClearOngoingWorkoutSurface<T>(AsyncValue<T?> activeSession) {
  return activeSession.hasValue && activeSession.value == null;
}
