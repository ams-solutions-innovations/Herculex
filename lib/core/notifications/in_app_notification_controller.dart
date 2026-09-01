import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/haptics.dart';
import 'in_app_notification_model.dart';

class InAppNotificationState {
  final InAppNotificationItem? current;
  final List<InAppNotificationItem> queue;
  final bool isDismissing;

  const InAppNotificationState({
    this.current,
    this.queue = const [],
    this.isDismissing = false,
  });

  InAppNotificationState copyWith({
    InAppNotificationItem? current,
    bool clearCurrent = false,
    List<InAppNotificationItem>? queue,
    bool? isDismissing,
  }) {
    return InAppNotificationState(
      current: clearCurrent ? null : (current ?? this.current),
      queue: queue ?? this.queue,
      isDismissing: isDismissing ?? this.isDismissing,
    );
  }
}

class InAppNotificationNotifier extends StateNotifier<InAppNotificationState> {
  InAppNotificationNotifier() : super(const InAppNotificationState());

  Timer? _autoDismissTimer;

  /// Post a new in-app notification / achievement.
  void show(InAppNotificationItem item) {
    if (state.current == null) {
      _display(item);
    } else {
      // Add to queue (avoid duplicates of exact same id)
      if (!state.queue.any((q) => q.id == item.id) &&
          state.current?.id != item.id) {
        state = state.copyWith(queue: [...state.queue, item]);
      }
    }
  }

  void _display(InAppNotificationItem item) {
    _autoDismissTimer?.cancel();
    Haptics.success();
    state = state.copyWith(current: item, isDismissing: false);

    _autoDismissTimer = Timer(item.duration, () {
      dismiss();
    });
  }

  /// Dismiss the currently visible notification and show next in queue if available.
  void dismiss() {
    _autoDismissTimer?.cancel();
    if (state.current == null) return;

    state = state.copyWith(isDismissing: true);

    // Wait for the exit animation to finish before advancing the queue.
    // Must match the overlay's _exitCtrl duration (collapse + fly-off).
    Future.delayed(const Duration(milliseconds: 560), () {
      if (!mounted) return;
      if (state.queue.isNotEmpty) {
        final next = state.queue.first;
        final remaining = state.queue.sublist(1);
        state = InAppNotificationState(queue: remaining);
        _display(next);
      } else {
        state = const InAppNotificationState();
      }
    });
  }

  /// Immediate reset / cancel.
  void clear() {
    _autoDismissTimer?.cancel();
    state = const InAppNotificationState();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }
}

final inAppNotificationControllerProvider =
    StateNotifierProvider<InAppNotificationNotifier, InAppNotificationState>((
      ref,
    ) {
      return InAppNotificationNotifier();
    });
