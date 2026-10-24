import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

final clockProvider = Provider<Clock>((_) => const SystemClock());

final localDayProvider =
    NotifierProvider.autoDispose<LocalDayNotifier, DateTime>(
      LocalDayNotifier.new,
    );

class LocalDayNotifier extends AutoDisposeNotifier<DateTime> {
  Timer? _timer;
  @override
  DateTime build() {
    final clock = ref.watch(clockProvider);
    ref.onDispose(() => _timer?.cancel());
    _schedule(clock);
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _schedule(Clock clock) {
    _timer?.cancel();
    final now = clock.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now), () {
      final current = clock.now();
      state = DateTime(current.year, current.month, current.day);
      _schedule(clock);
    });
  }
}
