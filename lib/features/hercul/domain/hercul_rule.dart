import 'hercul_context.dart';

/// Which voice a message is written in.
///
/// Both are authored for every rule. [honest] is blunt about *training* — never
/// about the user's body, weight or sex — and is opt-in behind a settings toggle
/// and an 18+ check.
enum HerculTone {
  normal('normal', 'Hercul'),
  honest('honest', 'Honest Hercul');

  const HerculTone(this.id, this.label);
  final String id;
  final String label;

  static HerculTone fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => HerculTone.normal);
}

/// What a rule is about. Drives the card's icon and colour, and lets the
/// evaluator avoid stacking three messages from the same subject.
enum HerculDomain {
  recovery,
  volume,
  nutrition,
  bodyweight,
  consistency,
  ergonomics;

  static HerculDomain fromId(String? id) => values.firstWhere(
        (d) => d.name == id,
        orElse: () => HerculDomain.consistency,
      );
}

enum ConditionOp {
  lt('<'),
  lte('<='),
  gt('>'),
  gte('>='),
  eq('=='),
  neq('!='),
  between('between');

  const ConditionOp(this.id);
  final String id;

  static ConditionOp? fromId(String? id) {
    for (final op in values) {
      if (op.id == id) return op;
    }
    return null;
  }
}

/// One clause of a rule's trigger.
class HerculCondition {
  final String signal;

  /// Subject for an argument-keyed signal — a muscle group or exercise slug.
  final String? arg;

  final ConditionOp op;

  /// Numeric comparand. Null for a label comparison.
  final double? value;

  /// Upper bound, [ConditionOp.between] only.
  final double? upper;

  /// Comparand for a label signal (`profile.goal == weightLoss`).
  final String? text;

  const HerculCondition({
    required this.signal,
    required this.op,
    this.arg,
    this.value,
    this.upper,
    this.text,
  });

  /// Null when the signal is absent — distinct from false, so the caller can
  /// skip the rule rather than treat missing data as a failed comparison.
  bool? evaluate(HerculContext context) {
    if (text != null) {
      final actual = context.label(signal);
      if (actual == null) return null;
      return switch (op) {
        ConditionOp.eq => actual == text,
        ConditionOp.neq => actual != text,
        // Ordering a label is meaningless; treat as unsatisfiable rather than
        // silently true.
        _ => false,
      };
    }

    final actual = context.number(signal, arg);
    if (actual == null || value == null) return null;
    return switch (op) {
      ConditionOp.lt => actual < value!,
      ConditionOp.lte => actual <= value!,
      ConditionOp.gt => actual > value!,
      ConditionOp.gte => actual >= value!,
      ConditionOp.eq => actual == value,
      ConditionOp.neq => actual != value,
      ConditionOp.between =>
        upper != null && actual >= value! && actual <= upper!,
    };
  }

  factory HerculCondition.fromJson(Map<String, dynamic> json) {
    final op = ConditionOp.fromId(json['op'] as String?);
    if (op == null) {
      throw FormatException('unknown operator "${json['op']}"');
    }
    return HerculCondition(
      signal: json['signal'] as String,
      arg: json['arg'] as String?,
      op: op,
      value: (json['value'] as num?)?.toDouble(),
      upper: (json['upper'] as num?)?.toDouble(),
      text: json['text'] as String?,
    );
  }
}

/// Where the card sends the user when they tap the message.
class HerculCta {
  /// `route` — push a path. `substitute` — open the substitution sheet for an
  /// exercise. `none` is expressed by omitting the object entirely.
  final String type;
  final String value;

  const HerculCta({required this.type, required this.value});

  factory HerculCta.fromJson(Map<String, dynamic> json) => HerculCta(
        type: json['type'] as String,
        value: json['value'] as String,
      );
}

/// One authored observation and the conditions under which Hercul makes it.
class HerculRule {
  final String id;
  final HerculDomain domain;

  /// 0–100, highest first. Ties break on id so ordering is deterministic.
  final int priority;

  /// Days this rule stays quiet after firing. Without it the same true fact —
  /// "you have not squatted in three weeks" — is said every single morning.
  final int cooldownDays;

  /// Signals that must be present. Anything referenced by [when] is implied;
  /// list a signal here when only the *copy* needs it.
  final List<String> requires;

  /// All clauses must hold. Deliberately AND-only: an `any` block is easy to
  /// add later and impossible to remove once the corpus depends on it.
  final List<HerculCondition> when;

  final Map<HerculTone, String> copy;
  final HerculCta? cta;

  const HerculRule({
    required this.id,
    required this.domain,
    required this.priority,
    required this.cooldownDays,
    required this.requires,
    required this.when,
    required this.copy,
    this.cta,
  });

  /// Every signal this rule reads, from its conditions and its `requires`.
  Set<String> get referencedSignals => {
        for (final c in when) c.signal,
        ...requires,
      };

  factory HerculRule.fromJson(Map<String, dynamic> json) {
    final copy = (json['copy'] as Map).cast<String, dynamic>();
    final normal = copy['normal'] as String?;
    final honest = copy['honest'] as String?;
    if (normal == null || honest == null) {
      throw FormatException(
        'rule "${json['id']}" must author both tones; '
        'a missing "honest" would silently fall back to the polite voice.',
      );
    }
    return HerculRule(
      id: json['id'] as String,
      domain: HerculDomain.fromId(json['domain'] as String?),
      priority: (json['priority'] as num?)?.toInt() ?? 50,
      cooldownDays: (json['cooldownDays'] as num?)?.toInt() ?? 7,
      requires: ((json['requires'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      when: ((json['when'] as List?) ?? const [])
          .map((e) => HerculCondition.fromJson((e as Map).cast()))
          .toList(),
      copy: {HerculTone.normal: normal, HerculTone.honest: honest},
      cta: json['cta'] == null
          ? null
          : HerculCta.fromJson((json['cta'] as Map).cast()),
    );
  }
}

/// A rule that fired, with its copy resolved for the chosen tone.
class HerculMessage {
  final String ruleId;
  final HerculDomain domain;
  final int priority;
  final String text;
  final HerculCta? cta;

  const HerculMessage({
    required this.ruleId,
    required this.domain,
    required this.priority,
    required this.text,
    this.cta,
  });
}
