import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/phone_motion_source.dart';
import '../data/rep_capture_service.dart';
import '../data/rep_tracking_repository.dart';
import '../domain/rep_calibration.dart';

final repTrackingRepositoryProvider = Provider<RepTrackingRepository>((ref) {
  return RepTrackingRepository(ref.watch(appDatabaseProvider));
});

/// The single settings row. Null, or a row whose `consentGrantedAt` is null,
/// both mean "consent screen not completed".
final repTrackingSettingsProvider = FutureProvider<RepTrackingSettingData?>((
  ref,
) {
  return ref.watch(repTrackingRepositoryProvider).settings();
});

/// Whether tracking may run for one catalogue slug. False whenever consent is
/// absent, regardless of the per-exercise preference.
final repTrackingEnabledForProvider = FutureProvider.family<bool, String>((
  ref,
  slug,
) {
  return ref.watch(repTrackingRepositoryProvider).isEnabledFor(slug);
});

/// The four-part key `calibrationProfileProvider` is keyed on. A `List`
/// key will not memoise correctly with Riverpod's `.family` (list equality
/// is identity-based, not structural) — this named record gets structural
/// `==`/`hashCode` for free.
typedef CalibrationProfileKey = ({
  String slug,
  String source,
  String? placement,
  String sensorType,
});

/// The learning profile for one exact (slug, source, placement, sensorType)
/// tuple. 10-05's calibration surface — the review sheet watches this,
/// keyed on the suggestion's own tuple, to decide whether to pre-fill an
/// RPE suggestion or show a "calibrating" progress line.
final calibrationProfileProvider =
    FutureProvider.family<CalibrationProfile, CalibrationProfileKey>((
      ref,
      key,
    ) {
      return ref
          .watch(repTrackingRepositoryProvider)
          .profileFor(
            slug: key.slug,
            source: key.source,
            placement: key.placement,
            sensorType: key.sensorType,
          );
    });

/// App-lifetime singleton: registers the three `WearSyncService.onWatchRep*`
/// bridge callbacks once and keeps their `stateStream`/`suggestions` alive
/// for whichever [RepTrackerPanel] is currently mounted. Disposed with the
/// provider container, not per-widget, so a capture in flight survives a
/// screen rebuild.
final repCaptureServiceProvider = Provider<RepCaptureService>((ref) {
  final service = RepCaptureService();
  ref.onDispose(service.dispose);
  return service;
});

/// App-lifetime singleton phone-accelerometer source (10-04 wiring; see
/// `RepCaptureService.buildPhoneSuggestion` for how its trace reaches
/// detection). The battery gate is best-effort: no battery-level plugin is
/// declared in `pubspec.yaml` (T-10-SC forbids this plan from adding one),
/// so the injected supplier always reports 100% until a future plan wires a
/// real one — the 15% refusal path itself is fully implemented and tested,
/// only the live reading is a stand-in.
final phoneMotionSourceProvider = Provider<PhoneMotionSource>((ref) {
  final source = PhoneMotionSource(
    repository: ref.watch(repTrackingRepositoryProvider),
    clock: () => DateTime.now().millisecondsSinceEpoch,
    batteryLevel: () async => 100,
  );
  ref.onDispose(source.dispose);
  return source;
});

/// Local, transient form state for the consent screen — nothing here is
/// persisted until the user taps the primary action. `source` starts at
/// `'wrist'`; a `phone` selection never carries a default placement (REP-02).
class RepConsentFormState {
  const RepConsentFormState({this.source = 'wrist', this.placement});

  final String source;
  final String? placement;

  /// Mirrors the consent screen's primary-action gate: always enabled for
  /// `wrist`, disabled for `phone` until a placement is chosen.
  bool get canSubmit => source == 'wrist' || placement != null;

  RepConsentFormState copyWith({
    String? source,
    String? Function()? placement,
  }) {
    return RepConsentFormState(
      source: source ?? this.source,
      placement: placement != null ? placement() : this.placement,
    );
  }
}

class RepConsentFormNotifier extends StateNotifier<RepConsentFormState> {
  RepConsentFormNotifier() : super(const RepConsentFormState());

  void selectSource(String source) {
    // Switching away from `phone` clears any placement already chosen so a
    // stale selection cannot silently re-enable the primary action for a
    // source that never asked for one.
    state = state.copyWith(
      source: source,
      placement: () => source == 'phone' ? state.placement : null,
    );
  }

  void selectPlacement(String placement) {
    state = state.copyWith(placement: () => placement);
  }
}

final repConsentFormProvider = StateNotifierProvider.autoDispose<
    RepConsentFormNotifier, RepConsentFormState>((ref) {
  return RepConsentFormNotifier();
});
