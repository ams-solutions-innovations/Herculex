import 'package:herculex/core/utils/clock.dart';

/// A settable [Clock] for tests.
class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime value) => _now = value;

  void advance(Duration d) => _now = _now.add(d);
}
