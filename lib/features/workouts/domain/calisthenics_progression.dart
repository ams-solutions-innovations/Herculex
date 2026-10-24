/// Authored strength paths. Levels are local to a movement and apparatus;
/// grips, explosive skills and kipping are not interchangeable strength tests.
class CalisthenicsLevel {
  const CalisthenicsLevel(
    this.slug,
    this.variant,
    this.label, {
    this.min = 5,
    this.max = 8,
    this.seconds = false,
  });
  final String slug;
  final String variant;
  final String label;
  final int min;
  final int max;
  final bool seconds;
  String get key => '$slug:$variant';
  String get prescription => '3 × $min–$max${seconds ? ' s' : ' reps'}';
}

class CalisthenicsPath {
  const CalisthenicsPath(
    this.id,
    this.label,
    this.levels, {
    this.parallelSlugs = const [],
    this.prerequisites = const [],
  });
  final String id;
  final String label;
  final List<CalisthenicsLevel> levels;
  final List<String> parallelSlugs;
  final List<String> prerequisites;
  Set<String> get slugs => {...levels.map((l) => l.slug), ...parallelSlugs};
}

const calisthenicsPaths = <CalisthenicsPath>[
  CalisthenicsPath('pull-up', 'Pull-Up', [
    CalisthenicsLevel('pull-up', 'band', 'Level I · Assisted'),
    CalisthenicsLevel('pull-up', 'bodyweight', 'Level II · Strict'),
    CalisthenicsLevel('pull-up', 'weighted', 'Level III · Weighted'),
  ]),
  CalisthenicsPath('pull-up-super-wide', 'Pull-Up · Super Wide', [
    CalisthenicsLevel(
      'assisted-pull-up-machine-super-wide',
      'machine_selectorized',
      'Level I · Machine assisted',
    ),
    CalisthenicsLevel('pull-up-super-wide', 'bodyweight', 'Level II · Strict'),
    CalisthenicsLevel('pull-up-super-wide', 'weighted', 'Level III · Weighted'),
  ]),
  CalisthenicsPath('pull-up-wide', 'Pull-Up · Wide Grip', [
    CalisthenicsLevel('pull-up-wide-grip', 'band', 'Level I · Assisted'),
    CalisthenicsLevel(
      'assisted-pull-up-machine-wide-grip',
      'machine_selectorized',
      'Level I · Machine assisted',
    ),
    CalisthenicsLevel('pull-up-wide-grip', 'bodyweight', 'Level II · Strict'),
    CalisthenicsLevel('pull-up-wide-grip', 'weighted', 'Level III · Weighted'),
  ]),
  CalisthenicsPath('pull-up-neutral', 'Pull-Up · Neutral Grip', [
    CalisthenicsLevel('pull-up-neutral-grip', 'band', 'Level I · Assisted'),
    CalisthenicsLevel(
      'assisted-pull-up-machine-neutral-grip',
      'machine_selectorized',
      'Level I · Machine assisted',
    ),
    CalisthenicsLevel(
      'pull-up-neutral-grip',
      'bodyweight',
      'Level II · Strict',
    ),
    CalisthenicsLevel(
      'pull-up-neutral-grip',
      'weighted',
      'Level III · Weighted',
    ),
  ]),
  CalisthenicsPath('push-up', 'Push-Up', [
    CalisthenicsLevel(
      'incline-push-up',
      'bodyweight',
      'Level I · Incline',
      min: 6,
      max: 12,
    ),
    CalisthenicsLevel(
      'standard-push-up',
      'bodyweight',
      'Level II · Standard',
      min: 6,
      max: 12,
    ),
    CalisthenicsLevel(
      'decline-push-up',
      'bodyweight',
      'Level III · Decline',
      min: 5,
      max: 10,
    ),
    CalisthenicsLevel(
      'archer-push-up',
      'bodyweight',
      'Level IV · Archer',
      min: 3,
      max: 6,
    ),
  ]),
  CalisthenicsPath('dip', 'Dip', [
    CalisthenicsLevel('chest-dips', 'band', 'Level I · Assisted'),
    CalisthenicsLevel('chest-dips', 'bodyweight', 'Level II · Strict'),
    CalisthenicsLevel('chest-dips', 'weighted', 'Level III · Weighted'),
  ]),
  CalisthenicsPath('ring-dip', 'Ring Dip', [
    CalisthenicsLevel('ring-dips', 'band', 'Level I · Assisted'),
    CalisthenicsLevel('ring-dips', 'bodyweight', 'Level II · Strict'),
    CalisthenicsLevel('ring-dips', 'weighted', 'Level III · Weighted'),
  ]),
  CalisthenicsPath(
    'bar-muscle-up',
    'Muscle-Up · Bar',
    [
      CalisthenicsLevel(
        'strict-muscle-up',
        'band',
        'Level I · Assisted strict',
        min: 2,
        max: 5,
      ),
      CalisthenicsLevel(
        'strict-muscle-up',
        'bodyweight',
        'Level II · Strict',
        min: 1,
        max: 3,
      ),
      CalisthenicsLevel(
        'strict-muscle-up',
        'weighted',
        'Level III · Weighted',
        min: 1,
        max: 3,
      ),
    ],
    parallelSlugs: ['kipping-muscle-up'],
    prerequisites: ['pull-up', 'chest-dips'],
  ),
  CalisthenicsPath(
    'ring-muscle-up',
    'Muscle-Up · Rings',
    [
      CalisthenicsLevel(
        'ring-muscle-up',
        'band',
        'Level I · Assisted strict',
        min: 2,
        max: 5,
      ),
      CalisthenicsLevel(
        'ring-muscle-up',
        'bodyweight',
        'Level II · Strict',
        min: 1,
        max: 3,
      ),
      CalisthenicsLevel(
        'ring-muscle-up',
        'weighted',
        'Level III · Weighted',
        min: 1,
        max: 3,
      ),
    ],
    prerequisites: ['pull-up', 'ring-dips'],
  ),
  CalisthenicsPath('handstand-push-up', 'Handstand Push-Up', [
    CalisthenicsLevel(
      'pike-push-up',
      'bodyweight',
      'Level I · Pike',
      min: 5,
      max: 8,
    ),
    CalisthenicsLevel(
      'handstand-push-up',
      'bodyweight',
      'Level II · Strict',
      min: 1,
      max: 5,
    ),
  ]),
  CalisthenicsPath('ring-row', 'Ring Row', [
    CalisthenicsLevel(
      'ring-row-feet-on-floor',
      'bodyweight',
      'Level I · Feet on floor',
      min: 6,
      max: 12,
    ),
    CalisthenicsLevel(
      'ring-row-feet-elevated',
      'bodyweight',
      'Level II · Feet elevated',
      min: 5,
      max: 10,
    ),
  ]),
  CalisthenicsPath('pistol-squat', 'Pistol Squat', [
    CalisthenicsLevel(
      'trx-assisted-pistol-squat',
      'bodyweight',
      'Level I · Assisted',
      min: 5,
      max: 8,
    ),
    CalisthenicsLevel(
      'pistol-squat',
      'bodyweight',
      'Level II · Strict',
      min: 3,
      max: 6,
    ),
    CalisthenicsLevel(
      'pistol-squat',
      'weighted',
      'Level III · Weighted',
      min: 3,
      max: 6,
    ),
  ]),
  CalisthenicsPath('ring-push-up', 'Ring Push-Up', [
    CalisthenicsLevel(
      'ring-push-up-knees',
      'bodyweight',
      'Level I · Knees',
      min: 6,
      max: 12,
    ),
    CalisthenicsLevel(
      'ring-push-up',
      'bodyweight',
      'Level II · Standard',
      min: 5,
      max: 10,
    ),
    CalisthenicsLevel(
      'ring-push-up-feet-elevated',
      'bodyweight',
      'Level III · Feet elevated',
      min: 5,
      max: 8,
    ),
  ]),
  CalisthenicsPath('l-sit', 'L-Sit · Floor', [
    CalisthenicsLevel(
      'l-sit-floor',
      'bodyweight',
      'Skill · Hold',
      min: 5,
      max: 20,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('ring-l-sit', 'L-Sit · Rings', [
    CalisthenicsLevel(
      'ring-l-sit',
      'bodyweight',
      'Skill · Hold',
      min: 5,
      max: 20,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('front-lever', 'Front Lever · Bar', [
    CalisthenicsLevel(
      'front-lever',
      'bodyweight',
      'Skill · Hold',
      min: 3,
      max: 15,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('ring-front-lever', 'Front Lever · Rings', [
    CalisthenicsLevel(
      'ring-front-lever',
      'bodyweight',
      'Skill · Hold',
      min: 3,
      max: 15,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('back-lever', 'Back Lever · Bar', [
    CalisthenicsLevel(
      'back-lever',
      'bodyweight',
      'Skill · Hold',
      min: 3,
      max: 15,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('ring-back-lever', 'Back Lever · Rings', [
    CalisthenicsLevel(
      'ring-back-lever',
      'bodyweight',
      'Skill · Hold',
      min: 3,
      max: 15,
      seconds: true,
    ),
  ]),
  CalisthenicsPath('planche', 'Planche', [
    CalisthenicsLevel(
      'full-planche',
      'bodyweight',
      'Skill · Hold',
      min: 3,
      max: 10,
      seconds: true,
    ),
  ]),
];

CalisthenicsPath? calisthenicsPathFor(String? slug) {
  for (final path in calisthenicsPaths) {
    if (path.slugs.contains(slug) ||
        (path.id == 'pull-up-wide' &&
            slug == 'band-assisted-pull-up-wide-grip') ||
        (path.id == 'pull-up-neutral' &&
            slug == 'band-assisted-pull-up-neutral-grip') ||
        (path.id == 'dip' && slug == 'band-assisted-dip')) {
      return path;
    }
  }
  return null;
}

CalisthenicsLevel? calisthenicsLevelFor(String? slug, String? variant) {
  if (slug == 'band-assisted-dip') {
    slug = 'chest-dips';
    variant = 'band';
  } else if (slug == 'band-assisted-pull-up-wide-grip') {
    slug = 'pull-up-wide-grip';
    variant = 'band';
  } else if (slug == 'band-assisted-pull-up-neutral-grip') {
    slug = 'pull-up-neutral-grip';
    variant = 'band';
  }
  if (slug?.startsWith('assisted-pull-up-machine-') ?? false)
    variant = 'machine_selectorized';
  final path = calisthenicsPathFor(slug);
  for (final level in path?.levels ?? const <CalisthenicsLevel>[]) {
    if (level.slug == slug && level.variant == (variant ?? 'bodyweight')) {
      return level;
    }
  }
  return null;
}

class CalisthenicsSet {
  const CalisthenicsSet({
    required this.value,
    this.load = 0,
    this.rpe,
    this.assistance = '',
    this.standard = true,
  });
  final int value;
  final double load;
  final int? rpe;

  /// Stable band ID/count/mode signature, never estimated kilograms.
  final String assistance;
  final bool standard;
}

class CalisthenicsPerformance {
  const CalisthenicsPerformance({
    required this.sessionId,
    required this.at,
    required this.levelKey,
    required this.sets,
  });
  final int sessionId;
  final DateTime at;
  final String levelKey;
  final List<CalisthenicsSet> sets;
}

class CalisthenicsRecommendation {
  const CalisthenicsRecommendation({
    required this.path,
    required this.current,
    required this.target,
    required this.ready,
    required this.successes,
    required this.value,
    required this.load,
    required this.reason,
    this.assistance = '',
  });
  final CalisthenicsPath path;
  final CalisthenicsLevel current;
  final CalisthenicsLevel target;
  final bool ready;
  final int successes;
  final int value;
  final double load;
  final String reason;
  final String assistance;
}

class CalisthenicsProgression {
  static const historyDays = 42;
  static const requiredSets = 3;

  /// Two recent successful sessions, at least 24h apart, with the same
  /// assistance and load. The thresholds are product defaults, not a validated
  /// diagnostic of skill readiness. Technique must be confirmed by the user.
  static CalisthenicsRecommendation recommend(
    CalisthenicsPath path,
    List<CalisthenicsPerformance> history,
    DateTime now, {
    double machineTransitionKg = 6,
  }) {
    final recent =
        history
            .where(
              (p) =>
                  !p.at.isAfter(now) &&
                  now.difference(p.at).inDays < historyDays,
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    final own = recent
        .where((p) => path.levels.any((l) => l.key == p.levelKey))
        .toList();
    final current = own.isEmpty
        ? path.levels.first
        : path.levels.firstWhere((l) => l.key == own.first.levelKey);
    final matching = own.where((p) => p.levelKey == current.key).toList();
    // One performance per session; split exercise rows are never two successes.
    final seen = <int>{};
    final last = matching.where((p) => seen.add(p.sessionId)).take(2).toList();
    final sets = last.isEmpty
        ? <CalisthenicsSet>[]
        : last.first.sets.where((s) => s.standard).toList();
    final load = sets.isEmpty ? 0.0 : sets.first.load;
    final signature = sets.isEmpty ? '' : sets.first.assistance;
    bool qualifies(CalisthenicsPerformance p) =>
        p.sets
            .where(
              (s) =>
                  s.standard &&
                  s.value >= current.max &&
                  (s.rpe == null || s.rpe! <= 80) &&
                  s.load == load &&
                  s.assistance == signature &&
                  s.load >= 0 &&
                  (current.variant == 'band'
                      ? signature.contains(':assistance') && s.load == 0
                      : signature.isEmpty),
            )
            .length >=
        requiredSets;
    var successes = 0;
    if (last.isNotEmpty && qualifies(last.first)) {
      successes = 1;
      if (last.length == 2 &&
          qualifies(last[1]) &&
          last.first.at.difference(last[1].at) >= const Duration(hours: 24)) {
        successes = 2;
      }
    }
    final foundations = path.prerequisites.every(
      (slug) => recent.any(
        (p) =>
            p.levelKey == '$slug:bodyweight' &&
            p.sets
                    .where(
                      (s) =>
                          s.standard &&
                          s.value >= 5 &&
                          s.load == 0 &&
                          s.assistance.isEmpty &&
                          (s.rpe == null || s.rpe! <= 80),
                    )
                    .length >=
                requiredSets,
      ),
    );
    final index = path.levels.indexOf(current);
    final next = {'machine_selectorized', 'band'}.contains(current.variant)
        ? path.levels.where((l) => l.variant == 'bodyweight').firstOrNull
        : index + 1 < path.levels.length
        ? path.levels[index + 1]
        : null;
    final ready =
        successes == 2 &&
        foundations &&
        next != null &&
        (current.variant != 'machine_selectorized' ||
            load <= machineTransitionKg);
    final target = ready ? next : current;
    final weakest = sets.isEmpty
        ? current.min
        : sets.map((s) => s.value).reduce((a, b) => a < b ? a : b);
    final value = matching.isEmpty
        ? current.min
        : ready
        ? target.min
        : (weakest + (current.seconds ? 2 : 1)).clamp(current.min, current.max);
    final nextLoad = ready
        ? (target.variant == 'weighted' ? 1.25 : 0.0)
        : current.variant == 'weighted' && successes == 2
        ? load + 1.25
        : load;
    final reason = ready
        ? 'Ready to try ${target.label}. Confirm controlled, pain-free full range before progressing.'
        : !foundations
        ? 'Build 3 × 5 strict ${path.prerequisites.join(' and ')} first. Keep practising assisted transitions.'
        : current.variant == 'band' && signature.isEmpty
        ? 'Log the assistance band on each set. Build reps, then try a lighter band before removing assistance.'
        : current.variant == 'weighted' && successes == 2
        ? 'Two successful sessions: add 1.25 kg and rebuild from ${current.min} reps.'
        : 'Build 3 × ${current.max}${current.seconds ? ' s' : ' reps'} twice, at least 24h apart, with the same setup and RPE ≤ 8 when logged ($successes/2).';
    return CalisthenicsRecommendation(
      path: path,
      current: current,
      target: target,
      ready: ready,
      successes: successes,
      value: nextLoad > load && !ready ? current.min : value,
      load: nextLoad,
      reason: reason,
      assistance: signature,
    );
  }
}
