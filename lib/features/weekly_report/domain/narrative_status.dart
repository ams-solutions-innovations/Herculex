/// What the Herculex AI narrative card shows (plain Dart, no Flutter).
///
/// There is deliberately no `skipped` value: when nothing measurable happened
/// in the week (D-06) the caller does not render the card at all, so the card
/// never has a "nothing to say" face.
///
/// The report controller maps `NarrativeFailureKind` onto [pending],
/// [offline] and [quotaExhausted]; the card itself reads no providers and is
/// driven purely by this value.
enum NarrativeStatus {
  /// First open of a week, the call is in flight (D-02).
  loading,

  /// A validated narrative is saved and shown.
  ready,

  /// The call failed or was rejected; no narrative is stored.
  pending,

  /// The device had no connection when the call was attempted.
  offline,

  /// The daily Herculex AI allowance is used up.
  quotaExhausted,
}
