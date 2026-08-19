import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../data/phone_motion_source.dart';
import '../domain/rep_suggestion.dart';
import '../domain/rep_tracking_eligibility.dart';
import '../domain/rep_tracking_profile.dart';
import 'rep_tracking_providers.dart';

/// The in-set surface rendered inside the active set card, for one eligible
/// exercise's next incomplete set.
///
/// Renders every [TrackerState] value explicitly; [TrackerState.disabled]
/// (no consent, or this exercise not opted in) renders nothing at all — no
/// placeholder, no padding (10-CONTEXT).
///
/// **Imports nothing from `lib/features/workouts/`** (REP-03) — it receives
/// everything it needs as constructor parameters and only ever *proposes*
/// via [onSuggestion]; it never writes anything itself.
class RepTrackerPanel extends ConsumerStatefulWidget {
  const RepTrackerPanel({
    super.key,
    required this.exerciseSlug,
    required this.sessionId,
    required this.setEntryId,
    required this.onSuggestion,
  });

  final String exerciseSlug;
  final int sessionId;
  final int setEntryId;

  /// Called once per completed capture with the terminal [RepSuggestion].
  /// The caller (`active_exercise_card.dart`) is responsible for opening the
  /// review sheet when the user ends the set — this panel never opens it
  /// itself and never writes anything.
  final ValueChanged<RepSuggestion> onSuggestion;

  @override
  ConsumerState<RepTrackerPanel> createState() => _RepTrackerPanelState();
}

class _RepTrackerPanelState extends ConsumerState<RepTrackerPanel> {
  TrackerState _captureState = TrackerState.ready;
  String? _reason;

  /// The last suggestion's `proposedReps` — [TrackerState.countOnly] shows
  /// this alongside the "no RPE" note; a manual capture (nothing detected)
  /// leaves it null.
  int? _lastProposedReps;

  /// True only after the user's own tap on "Start tracking" below. Stream
  /// events are ignored until this flips — the panel must never reflect a
  /// tracking state the user did not themselves start (10-CONTEXT
  /// "Tracking never starts without a user tap").
  bool _armed = false;

  StreamSubscription<TrackerState>? _wristStateSub;
  StreamSubscription<TrackerState>? _phoneStateSub;
  StreamSubscription<RepSuggestion>? _suggestionSub;
  StreamSubscription<PhoneMotionCaptureResult>? _phoneEndSub;

  @override
  void initState() {
    super.initState();
    // Subscribing here only *observes* the shared services — it never calls
    // a start method. The user's tap in [_onStartTap] is the only caller of
    // either start() below.
    final capture = ref.read(repCaptureServiceProvider);
    final phone = ref.read(phoneMotionSourceProvider);

    _wristStateSub = capture.stateStream.listen((s) {
      if (!_armed || !mounted) return;
      setState(() {
        _captureState = s;
        _reason = capture.stateReason;
      });
    });
    _phoneStateSub = phone.stateStream.listen((s) {
      if (!_armed || !mounted) return;
      setState(() {
        _captureState = s;
        _reason = phone.stateReason;
      });
    });
    // Deliberately does *not* flip `_armed` back to false here: the
    // suggestions stream and the state stream are two independent
    // StreamControllers, and nothing guarantees this listener runs before
    // the state-stream listener above processes the very same capture's
    // terminal `countOnly`/`manual` event — clearing `_armed` here first
    // would make that state update lose the race and get silently dropped.
    // `_armed` resets in [didUpdateWidget] once this panel starts tracking a
    // different set (a fresh "ready" state for the next set).
    _suggestionSub = capture.suggestions.listen((s) {
      if (s.exerciseSlug != widget.exerciseSlug || !mounted) return;
      setState(() => _lastProposedReps = s.proposedReps);
      widget.onSuggestion(s);
    });
    _phoneEndSub = phone.captureEnded.listen((result) async {
      if (!mounted) return;
      final settings = await ref.read(repTrackingRepositoryProvider).settings();
      final placement = settings?.phonePlacement;
      if (placement == null) return;
      final suggestion = ref.read(repCaptureServiceProvider).buildPhoneSuggestion(
            captureId: 'phone-${DateTime.now().millisecondsSinceEpoch}',
            exerciseSlug: widget.exerciseSlug,
            trace: result.trace,
            placement: placement,
            stoppedReason: result.stoppedReason,
          );
      if (!mounted) return;
      setState(() => _lastProposedReps = suggestion.proposedReps);
      widget.onSuggestion(suggestion);
    });
  }

  @override
  void didUpdateWidget(covariant RepTrackerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The caller moved this panel on to a different set (the previous one
    // was completed and reviewed) — reset to a fresh "ready" for the new
    // set rather than carrying over the previous set's terminal state.
    if (oldWidget.setEntryId != widget.setEntryId) {
      _armed = false;
      _captureState = TrackerState.ready;
      _reason = null;
      _lastProposedReps = null;
    }
  }

  @override
  void dispose() {
    _wristStateSub?.cancel();
    _phoneStateSub?.cancel();
    _suggestionSub?.cancel();
    _phoneEndSub?.cancel();
    super.dispose();
  }

  /// Where this exercise has to be sensed from.
  ///
  /// Read from the capability profile, never from a stored preference. A
  /// pull-up needs the pocket because the hands are anchored to a bar and the
  /// wrist genuinely does not travel; a bench press is sensed at the wrist.
  /// Offering that as a setting only invites a wrong answer, which then
  /// presents to the user as the tracker being broken.
  SensorSite? get _site => sensorSiteFor(widget.exerciseSlug);

  Future<void> _onStartTap() async {
    setState(() {
      _armed = true;
      _captureState = TrackerState.tracking;
      _reason = null;
    });
    if (_site == SensorSite.pocket) {
      final refusal = await ref.read(phoneMotionSourceProvider).start();
      if (refusal != null && mounted) {
        setState(() {
          _captureState = TrackerState.manual;
          _reason = refusal.reason;
        });
      }
    }
    // For the wrist source there is nothing to call here: capture begins
    // when the watch's own `/herculex/reps/capture_start` message arrives
    // (the user's tap on the watch itself). `_armed` is what lets this panel
    // start reflecting that once it does, without ever initiating it.
  }

  Future<void> _onStopTap() async {
    if (_site == SensorSite.pocket) {
      ref.read(phoneMotionSourceProvider).stop();
    } else {
      final captureId =
          ref.read(repCaptureServiceProvider).activeCaptureIdFor(widget.exerciseSlug);
      if (captureId != null) {
        ref.read(repCaptureServiceProvider).abort(captureId, reason: 'stopped from phone');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync =
        ref.watch(repTrackingEnabledForProvider(widget.exerciseSlug));
    final enabled = enabledAsync.asData?.value ?? false;
    final effectiveState = enabled ? _captureState : TrackerState.disabled;

    switch (effectiveState) {
      case TrackerState.disabled:
        return const SizedBox.shrink();
      case TrackerState.ready:
        return _shell(
          context,
          child: Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _site == SensorSite.pocket
                      // Said before the set, not after it produced nothing.
                      // There is no threshold that recovers a pull-up from
                      // the wrist — the hand is locked to the bar — so the
                      // only useful moment to mention the pocket is now.
                      ? 'Put your phone in a pocket to count this one.'
                      : 'Rep counting is ready for this set.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _onStartTap,
                child: const Text('Start'),
              ),
            ],
          ),
        );
      case TrackerState.tracking:
        return _shell(
          context,
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tracking…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              TextButton(
                onPressed: _onStopTap,
                child: const Text('Stop'),
              ),
            ],
          ),
        );
      case TrackerState.countOnly:
        return _shell(
          context,
          neutral: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tag, size: 18, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastProposedReps != null
                          ? '$_lastProposedReps reps proposed — no RPE suggestion'
                          : 'Reps proposed — no RPE suggestion',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_reason != null)
                      Text(
                        _reason!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      case TrackerState.manual:
        return _shell(
          context,
          neutral: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.edit_note, size: 18, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log this set manually',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_reason != null)
                      Text(
                        _reason!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  /// Shared neutral/informational chrome. `countOnly` and `manual` are
  /// expected states, not failures, so they never get the error/warning
  /// treatment (10-CONTEXT) — `neutral` only changes the border tone, never
  /// to red/amber.
  Widget _shell(BuildContext context, {required Widget child, bool neutral = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (neutral ? AppColors.secondary : AppColors.primary)
                .withValues(alpha: 0.3),
          ),
        ),
        child: child,
      ),
    );
  }
}
