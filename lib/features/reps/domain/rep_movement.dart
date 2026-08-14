/// The movement family a rep-tracked exercise belongs to.
///
/// **This is the single declaration of [RepMovement] in the repository.**
/// `RepDetectorConfig.forMovement` (10-02), `RepSuggestion` (10-03b) and the
/// calibration profile keys (10-05) all import this file. A second
/// declaration anywhere else is a merge-time compile error, and that is
/// deliberate — the detector defaults, the suggestion payload and the profile
/// key must all agree on one enum or a profile trained on pull-ups can be
/// applied to dips.
///
/// It lives in its own file rather than inside `rep_tracking_eligibility.dart`
/// so 10-02 can import the enum without pulling in the slug list, which is a
/// data/consent concern the pure detection engine has no business knowing
/// about.
///
/// The mapping from a catalogue slug to a [RepMovement] is `movementFor` in
/// `rep_tracking_eligibility.dart`.
enum RepMovement { pullUp, dip }
