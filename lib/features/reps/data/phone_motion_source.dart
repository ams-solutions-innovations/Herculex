import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../domain/motion_sample.dart';
import '../domain/rep_suggestion.dart';
import 'rep_tracking_repository.dart';

/// Millisecond clock, injected so the 5-minute cap is fake-testable rather
/// than tied to wall time.
typedef MonotonicClockMs = int Function();

/// Current battery level of the capturing device, 0-100. Injected (async,
/// like the real platform lookup) so the 15 % gate is fake-testable.
typedef BatteryLevelSupplier = Future<int> Function();

/// Why [PhoneMotionSource.start] refused to begin capture. Typed rather than
/// a thrown exception, so a refusal is a normal control-flow value the
/// caller branches on, not something it has to catch.
class PhoneMotionStartRefusal {
  const PhoneMotionStartRefusal._(this.reason);

  final String reason;

  /// REP-02: the phone accelerometer is used only when a placement is
  /// explicitly selected. Never defaulted.
  static const PhoneMotionStartRefusal noPlacement = PhoneMotionStartRefusal._(
    'no phone placement selected — count not verified',
  );

  static const PhoneMotionStartRefusal lowBattery = PhoneMotionStartRefusal._(
    'phone battery too low — count not verified',
  );

  static const PhoneMotionStartRefusal alreadyRunning = PhoneMotionStartRefusal._(
    'a phone capture is already running',
  );

  @override
  String toString() => 'PhoneMotionStartRefusal($reason)';
}

/// The trace and how capture ended. `stoppedReason` is `'user'` or `'cap'` —
/// there is no watch-style batching failure mode on the phone, since the
/// samples never leave the device that captured them.
class PhoneMotionCaptureResult {
  const PhoneMotionCaptureResult({
    required this.trace,
    required this.stoppedReason,
  });

  final MotionTrace trace;
  final String stoppedReason;
}

/// Phone-local accelerometer source producing the **identical `MotionTrace`
/// shape** the wrist path does, so `RepDetector` is source-agnostic.
///
/// Refuses to start without an explicit [RepTrackingSettings.phonePlacement]
/// (REP-02) and without at least 15 % battery, and hard-caps a capture at 5
/// minutes — all three gates fake-tested via the injected [MonotonicClockMs]
/// and [BatteryLevelSupplier] rather than `DateTime.now()` or a static
/// plugin lookup.
class PhoneMotionSource {
  PhoneMotionSource({
    required RepTrackingRepository repository,
    required MonotonicClockMs clock,
    required BatteryLevelSupplier batteryLevel,
    Stream<MotionSample> Function()? linearAccelerationStream,
    Stream<MotionSample> Function()? accelerometerStream,
    Duration captureCap = const Duration(minutes: 5),
    int minimumBatteryPercent = 15,
  })  : _repository = repository,
        _clock = clock,
        _batteryLevel = batteryLevel,
        _linearAccelerationStream =
            linearAccelerationStream ?? _defaultLinearAccelerationStream,
        _accelerometerStream = accelerometerStream ?? _defaultAccelerometerStream,
        _captureCap = captureCap,
        _minimumBatteryPercent = minimumBatteryPercent;

  final RepTrackingRepository _repository;
  final MonotonicClockMs _clock;
  final BatteryLevelSupplier _batteryLevel;
  final Stream<MotionSample> Function() _linearAccelerationStream;
  final Stream<MotionSample> Function() _accelerometerStream;
  final Duration _captureCap;
  final int _minimumBatteryPercent;

  StreamSubscription<MotionSample>? _subscription;
  List<MotionSample> _samples = [];
  String? _sensorType;
  int? _startedAtMs;

  final StreamController<TrackerState> _stateController =
      StreamController<TrackerState>.broadcast();
  Stream<TrackerState> get stateStream => _stateController.stream;

  /// Fires whenever a capture ends, including a cap firing autonomously
  /// mid-capture (there is otherwise no way for a caller to learn what was
  /// collected when the 5-minute cap — not an explicit [stop] call — is what
  /// ended the set).
  final StreamController<PhoneMotionCaptureResult> _captureEndedController =
      StreamController<PhoneMotionCaptureResult>.broadcast();
  Stream<PhoneMotionCaptureResult> get captureEnded => _captureEndedController.stream;

  String? get stateReason => _stateReason;
  String? _stateReason;

  bool get isCapturing => _subscription != null;

  static Stream<MotionSample> _defaultLinearAccelerationStream() =>
      userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) => MotionSample(0, e.x, e.y, e.z));

  static Stream<MotionSample> _defaultAccelerometerStream() =>
      accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) => MotionSample(0, e.x, e.y, e.z));

  /// Attempts to start a capture. Returns a [PhoneMotionStartRefusal] and
  /// registers **no** subscription when refused; returns null on success.
  Future<PhoneMotionStartRefusal?> start() async {
    if (_subscription != null) {
      return PhoneMotionStartRefusal.alreadyRunning;
    }

    final settings = await _repository.settings();
    if (settings?.phonePlacement == null) {
      _emitManual(PhoneMotionStartRefusal.noPlacement.reason);
      return PhoneMotionStartRefusal.noPlacement;
    }

    final battery = await _batteryLevel();
    if (battery < _minimumBatteryPercent) {
      _emitManual(PhoneMotionStartRefusal.lowBattery.reason);
      return PhoneMotionStartRefusal.lowBattery;
    }

    Stream<MotionSample> stream;
    String sensorType;
    try {
      stream = _linearAccelerationStream();
      sensorType = MotionSensorType.linearAcceleration;
    } catch (_) {
      // Linear acceleration unavailable on this device — fall back to raw
      // accelerometer. The profile records which was used (10-CONTEXT
      // "Sensor and sampling") because the two are not interchangeable.
      stream = _accelerometerStream();
      sensorType = MotionSensorType.accelerometer;
    }

    _samples = [];
    _sensorType = sensorType;
    _startedAtMs = _clock();
    _stateReason = null;

    try {
      _subscription = stream.listen(_onSample, onError: (_) {});
    } catch (_) {
      _subscription?.cancel();
      _subscription = null;
      return PhoneMotionStartRefusal.alreadyRunning;
    }

    _stateController.add(TrackerState.tracking);
    return null;
  }

  void _onSample(MotionSample raw) {
    final startedAtMs = _startedAtMs;
    if (startedAtMs == null) return;
    final tMs = _clock() - startedAtMs;
    // The 5-minute cap is enforced against the injected clock on every
    // sample, not a real-time Timer, so it stays driven by the same fake
    // clock a test controls — the triggering sample lands past the cap and
    // is not appended, matching "stops capture, keeps what was collected".
    if (tMs >= _captureCap.inMilliseconds) {
      _stop(reason: 'cap');
      return;
    }
    _samples.add(MotionSample(tMs, raw.x, raw.y, raw.z));
  }

  /// Ends capture normally (`reason == 'user'`) and returns the collected
  /// trace, or null if nothing was running.
  PhoneMotionCaptureResult? stop({String reason = 'user'}) => _stop(reason: reason);

  PhoneMotionCaptureResult? _stop({required String reason}) {
    if (_subscription == null) return null;
    _subscription!.cancel();
    _subscription = null;
    final trace = MotionTrace(
      samples: List.unmodifiable(_samples),
      sensorType: _sensorType!,
    );
    _samples = [];
    final result = PhoneMotionCaptureResult(trace: trace, stoppedReason: reason);
    _captureEndedController.add(result);
    return result;
  }

  void _emitManual(String reason) {
    _stateReason = reason;
    _stateController.add(TrackerState.manual);
  }

  /// Cancels any live subscription in a `finally`-equivalent single call, so
  /// disposal never leaves a subscription registered.
  void dispose() {
    try {
      _subscription?.cancel();
    } finally {
      _subscription = null;
      _stateController.close();
      _captureEndedController.close();
    }
  }
}
