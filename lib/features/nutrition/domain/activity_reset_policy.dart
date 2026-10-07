import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

/// What the Profile ActivityLevel picker should do when a tile is tapped.
enum ActivityResetAction {
  /// The tapped level is already selected.
  none,

  /// Still calibrating: the pick is the seed, save immediately (D-13).
  saveNow,

  /// Calibrated: ask before reseeding (D-14).
  confirm,
}

/// State rules, branching and copy for the Profile activity-level reset.
///
/// D-14 (a reset reseeds only and never discards estimate history) and D-15
/// (a reset does not force a Measured user back to Calibrating, because the
/// estimator's observed path never reads the seed) are properties of the
/// design, not of this class. This policy only chooses the copy and whether a
/// confirm dialog is needed ([actionFor], [isCalibrated]).
abstract final class ActivityResetPolicy {
  static const String dialogTitle = 'Reset activity level?';
  static const String dialogBody =
      "This becomes your new starting point. It won't erase your "
      'calibration history.';
  static const String keepLabel = 'Keep Current Level';
  static const String resetLabel = 'Reset Activity Level';

  static const String _captionCalibrating =
      "Your starting estimate. We'll refine it automatically as you log.";
  static const String _captionCalibrated =
      'Manual reset. Use this only if your routine changed a lot. '
      'It reseeds the estimate and keeps your history.';

  static const String _snackbarMeasured =
      'Saved. Your estimate stays measured from your logs.';
  static const String _snackbarOther =
      "Saved. We'll use this as the starting point at the next "
      'recalibration.';

  /// True once a non-coldStart estimate exists (classifier or observed,
  /// fresh or held).
  static bool isCalibrated(TdeeEstimateResult? latest) =>
      latest != null && latest.method != TdeeMethod.coldStart;

  /// True only for a fresh observed estimate. The held (aging) state is not
  /// measured, so it gets the D-14 snackbar.
  static bool isMeasured(TdeeEstimateResult? latest) =>
      latest != null &&
      latest.method == TdeeMethod.observed &&
      latest.observedQualified;

  static ActivityResetAction actionFor({
    required bool isSameLevel,
    required bool calibrated,
  }) {
    if (isSameLevel) return ActivityResetAction.none;
    return calibrated
        ? ActivityResetAction.confirm
        : ActivityResetAction.saveNow;
  }

  static String caption({required bool calibrated}) =>
      calibrated ? _captionCalibrated : _captionCalibrating;

  static String snackbar({required bool measured}) =>
      measured ? _snackbarMeasured : _snackbarOther;
}
