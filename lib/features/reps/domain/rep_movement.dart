/// The movement family a rep-tracked exercise belongs to.
///
/// **This is the single declaration of [RepMovement] in the repository.**
/// `RepDetectorConfig.forMovement`, `RepSuggestion` and the calibration
/// profile keys all import this file. A second declaration anywhere else is a
/// merge-time compile error, and that is deliberate — the detector defaults,
/// the suggestion payload and the profile key must all agree on one enum or a
/// profile trained on pull-ups can be applied to dips.
///
/// It lives in its own file rather than inside `rep_tracking_eligibility.dart`
/// so the pure detection engine can import the enum without pulling in the
/// catalogue lookup, which is a data/consent concern it has no business
/// knowing about.
///
/// ## Why these fifteen
///
/// A family is a **calibration key**, not a taxonomy of exercise names. Two
/// exercises belong together exactly when the same detector thresholds and the
/// same learned RPE coefficients apply to both — which means they must put the
/// *sensor-bearing segment* through a similar motion.
///
/// That is why [bodyweightPull] exists separately from [bodyweightPush] even
/// though both are hands-anchored bodyweight work sensed at the hip: an
/// inverted row and a push-up drive the body along different axes at different
/// cadences. And it is why [verticalPullDown] is not [verticalPull] — a lat
/// pulldown is seated with the hands travelling, a pull-up is hanging with the
/// hands still. Sharing a family between those would train one profile on two
/// unrelated signals.
///
/// [id] matches the `family` string in `assets/data/rep_tracking_profiles.json`
/// exactly; `test/rep_tracking_profiles_test.dart` fails the build if the two
/// vocabularies drift apart.
enum RepMovement {
  // ── Hands anchored: sensed at the hip, from a phone in a front pocket ────
  /// Hanging, hands still, body travels vertically past the grip — the
  /// pull-up and chin-up families, plus hanging core work.
  verticalPull('verticalPull'),

  /// Hands planted, body travels — dips, push-ups, handstand push-ups.
  bodyweightPush('bodyweightPush'),

  /// Hands on a fixed bar or strap, body travels horizontally — inverted rows.
  bodyweightPull('bodyweightPull'),

  // ── Hands travel: sensed at the wrist, from the watch ────────────────────
  /// Bench presses, dumbbell presses, machine chest presses.
  horizontalPush('horizontalPush'),

  /// Overhead presses and push presses.
  verticalPush('verticalPush'),

  /// Rows where the torso is braced and the hands travel.
  horizontalPull('horizontalPull'),

  /// Seated pulldowns — hands travel, body does not.
  verticalPullDown('verticalPullDown'),

  /// Elbow flexion: every curl.
  elbowFlexion('elbowFlexion'),

  /// Elbow extension: pushdowns, skullcrushers, overhead triceps work.
  elbowExtension('elbowExtension'),

  /// Straight-arm shoulder arcs: lateral and front raises, flyes.
  shoulderRaise('shoulderRaise'),

  /// Knee-dominant patterns where the load travels with the torso.
  squat('squat'),

  /// Hip-dominant patterns.
  hinge('hinge'),

  /// Single-leg knee-dominant patterns.
  lunge('lunge'),

  /// Trunk flexion and rotation where the hands ride the torso.
  coreFlexion('coreFlexion'),

  /// Short-range work — shrugs, calf raises, rack pulls. Countable, but never
  /// confidently enough to carry an RPE suggestion, so this family is pinned
  /// to the `countOnly` tier.
  smallRom('smallRom');

  const RepMovement(this.id);

  /// Stable wire/asset identifier. Never derive this from [name] — the enum
  /// may be reordered or renamed, and a calibration profile keyed on a
  /// renamed family would silently apply the wrong coefficients.
  final String id;

  /// The family with this [id], or null when [id] is unknown or null.
  ///
  /// Deliberately null-returning rather than throwing or defaulting: an
  /// unrecognised family means the asset and this enum disagree, and the
  /// correct response is to offer no tracking for that exercise, not to guess.
  static RepMovement? fromId(String? id) {
    if (id == null) return null;
    for (final m in RepMovement.values) {
      if (m.id == id) return m;
    }
    return null;
  }
}
