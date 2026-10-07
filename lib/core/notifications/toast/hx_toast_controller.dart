import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/toast/hx_toast_model.dart';
import 'package:herculex/design_system/theme/haptics.dart';

class HxToastState {
  final HxToastItem? current;
  final List<HxToastItem> queue;
  final bool isDismissing;

  const HxToastState({
    this.current,
    this.queue = const [],
    this.isDismissing = false,
  });

  HxToastState copyWith({
    HxToastItem? current,
    bool clearCurrent = false,
    List<HxToastItem>? queue,
    bool? isDismissing,
  }) {
    return HxToastState(
      current: clearCurrent ? null : (current ?? this.current),
      queue: queue ?? this.queue,
      isDismissing: isDismissing ?? this.isDismissing,
    );
  }
}

class HxToastNotifier extends StateNotifier<HxToastState> {
  HxToastNotifier() : super(const HxToastState());

  Timer? _autoDismissTimer;

  /// Post a new toast. Queues it if one is already showing.
  void show(HxToastItem item) {
    if (state.current == null) {
      _display(item);
    } else {
      if (!state.queue.any((q) => q.id == item.id) &&
          state.current?.id != item.id) {
        state = state.copyWith(queue: [...state.queue, item]);
      }
    }
  }

  void _display(HxToastItem item) {
    _autoDismissTimer?.cancel();
    Haptics.success();
    state = state.copyWith(current: item, isDismissing: false);

    _autoDismissTimer = Timer(item.duration, dismiss);
  }

  /// Dismiss the currently visible toast and show the next queued one, if any.
  void dismiss() {
    _autoDismissTimer?.cancel();
    if (state.current == null) return;

    state = state.copyWith(isDismissing: true);

    // Must match the card's exit-animation duration in hx_toast_overlay.dart.
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      if (state.queue.isNotEmpty) {
        final next = state.queue.first;
        final remaining = state.queue.sublist(1);
        state = HxToastState(queue: remaining);
        _display(next);
      } else {
        state = const HxToastState();
      }
    });
  }

  void clear() {
    _autoDismissTimer?.cancel();
    state = const HxToastState();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }
}

final hxToastControllerProvider =
    StateNotifierProvider<HxToastNotifier, HxToastState>((ref) {
      return HxToastNotifier();
    });
