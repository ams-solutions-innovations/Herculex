import 'rep_movement.dart';

/// One entry in the closed, 11-fixture motion-trace corpus REP-06 requires.
///
/// Verbatim from `10-02-PLAN.md` Task 5's `<how-to-verify>` table — do not
/// invent or drop a row. [movement] is `null` for the two noise fixtures
/// (`noise_walking_60s_0reps`, `noise_regrip_rest_45s_0reps`), which have no
/// countable movement at all.
class FixtureSpec {
  const FixtureSpec({
    required this.name,
    required this.purpose,
    required this.movement,
    required this.source,
    required this.placement,
    required this.targetRepCount,
  });

  /// Base file name, without extension — the `.csv`/`.json` pair share it.
  final String name;

  /// Why this fixture exists, from the 10-02 table's "Purpose" column.
  final String purpose;

  /// `null` only for the two noise fixtures.
  final RepMovement? movement;

  /// `'wrist'` | `'phone'`.
  final String source;

  /// `'pocket_front'` | `'armband'` | `null` (wrist source never has one).
  final String? placement;

  /// Ground-truth rep count this fixture's name promises; 0 for the noise
  /// fixtures. This is the *target*, not a substitute for the developer's own
  /// human count entered at capture time — see [FixtureRecorder.save] (Task
  /// 2) which takes `repCount` as an explicit parameter.
  final int targetRepCount;
}

/// The closed list of 11 required fixtures, verbatim from
/// `10-02-PLAN.md`'s Task 5 table. REP-06 requires exactly these — widening
/// or narrowing this list is a plan-level decision, not something this file
/// or the recording screen may do unilaterally.
const List<FixtureSpec> requiredFixtures = [
  FixtureSpec(
    name: 'pullup_wrist_clean_8reps',
    purpose: 'baseline accuracy',
    movement: RepMovement.verticalPull,
    source: 'wrist',
    placement: null,
    targetRepCount: 8,
  ),
  FixtureSpec(
    name: 'pullup_wrist_grinder_5reps',
    purpose: 'slowing final reps, uneven cadence',
    movement: RepMovement.verticalPull,
    source: 'wrist',
    placement: null,
    targetRepCount: 5,
  ),
  FixtureSpec(
    name: 'pullup_wrist_kipping_10reps',
    purpose: 'high-amplitude noise between reps',
    movement: RepMovement.verticalPull,
    source: 'wrist',
    placement: null,
    targetRepCount: 10,
  ),
  FixtureSpec(
    name: 'pullup_wrist_interrupted_6reps',
    purpose: 'capture cut mid-set',
    movement: RepMovement.verticalPull,
    source: 'wrist',
    placement: null,
    targetRepCount: 6,
  ),
  FixtureSpec(
    name: 'dip_wrist_clean_12reps',
    purpose: 'baseline, faster cadence than pull-ups',
    movement: RepMovement.bodyweightPush,
    source: 'wrist',
    placement: null,
    targetRepCount: 12,
  ),
  FixtureSpec(
    name: 'dip_wrist_partial_rom_10reps',
    purpose: 'amplitude gate under shrinking ROM',
    movement: RepMovement.bodyweightPush,
    source: 'wrist',
    placement: null,
    targetRepCount: 10,
  ),
  FixtureSpec(
    name: 'ringdip_wrist_8reps',
    purpose: 'the least stable eligible movement',
    // ring-dips maps to RepMovement.bodyweightPush (rep_tracking_eligibility.dart) —
    // there is no separate RepMovement.ringDip in the single-source enum.
    movement: RepMovement.bodyweightPush,
    source: 'wrist',
    placement: null,
    targetRepCount: 8,
  ),
  FixtureSpec(
    name: 'pullup_phone_pocket_8reps',
    purpose: 'phone source, pocket placement',
    movement: RepMovement.verticalPull,
    source: 'phone',
    placement: 'pocket_front',
    targetRepCount: 8,
  ),
  FixtureSpec(
    name: 'pullup_phone_armband_8reps',
    purpose: 'phone source, armband placement — the placement-change axis of REP-06',
    movement: RepMovement.verticalPull,
    source: 'phone',
    placement: 'armband',
    targetRepCount: 8,
  ),
  FixtureSpec(
    name: 'noise_walking_60s_0reps',
    purpose: 'false-positive resistance',
    movement: null,
    source: 'wrist',
    placement: null,
    targetRepCount: 0,
  ),
  FixtureSpec(
    name: 'noise_regrip_rest_45s_0reps',
    purpose: 're-gripping and resting between sets',
    movement: null,
    source: 'wrist',
    placement: null,
    targetRepCount: 0,
  ),
];

/// Recorded state of one [FixtureSpec] against the on-device corpus.
///
/// [needsRedo] is never assigned by [FixtureCorpusStatus.evaluate] — it
/// exists purely as a state the developer can set by hand later (a fixture
/// recorded but later judged bad), read from wherever a future revision of
/// this tool persists it. This plan's `evaluate` only ever produces
/// [missing] or [recorded].
enum FixtureRecordState { missing, recorded, needsRedo }

/// Sufficiency of the on-device fixture corpus against [requiredFixtures].
///
/// Always derived from a fresh scan of what actually exists on disk
/// ([FixtureRecorder.listRecorded]) — never from in-memory state carried
/// across screens or app launches, so a fresh launch always reports the true
/// recorded/missing status.
class FixtureCorpusStatus {
  const FixtureCorpusStatus({required this.byName, required this.sufficient});

  final Map<String, FixtureRecordState> byName;

  /// True iff every one of the 11 [requiredFixtures] is [FixtureRecordState.recorded].
  final bool sufficient;

  /// Specs still missing, in [requiredFixtures] order.
  List<FixtureSpec> get missingSpecs => [
        for (final spec in requiredFixtures)
          if (byName[spec.name] != FixtureRecordState.recorded) spec,
      ];

  static FixtureCorpusStatus evaluate(List<String> recordedNames) {
    final recorded = recordedNames.toSet();
    final byName = <String, FixtureRecordState>{
      for (final spec in requiredFixtures)
        spec.name: recorded.contains(spec.name)
            ? FixtureRecordState.recorded
            : FixtureRecordState.missing,
    };
    final sufficient =
        byName.values.every((s) => s == FixtureRecordState.recorded);
    return FixtureCorpusStatus(byName: byName, sufficient: sufficient);
  }
}
