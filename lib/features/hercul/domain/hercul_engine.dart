import 'hercul_context.dart';
import 'hercul_rule.dart';

/// Matches authored rules against the user's data and renders the copy.
///
/// A pure function of ([HerculContext], rules, tone, cooldown log) so every rule
/// in the corpus can be unit-tested against a synthetic context without a
/// database — the same shape as `CnsTrends` and `MuscleRecoveryV3`.
abstract final class HerculEngine {
  /// How many messages the dashboard card shows. A coaching card that lists
  /// everything wrong at once reads as nagging and gets switched off.
  static const defaultLimit = 3;

  /// Rules that fire, highest priority first.
  ///
  /// [lastFiredAt] maps rule id to the last time it was shown; a rule inside its
  /// cooldown is skipped. [limit] caps the result, and at most one message per
  /// domain survives so three recovery findings do not crowd out everything else.
  static List<HerculMessage> evaluate({
    required HerculContext context,
    required List<HerculRule> rules,
    HerculTone tone = HerculTone.normal,
    Map<String, DateTime> lastFiredAt = const {},
    int limit = defaultLimit,
  }) {
    final fired = <HerculRule>[];

    for (final rule in rules) {
      if (_isCoolingDown(rule, lastFiredAt[rule.id], context.now)) continue;
      if (!_hasRequiredSignals(rule, context)) continue;

      var matched = true;
      for (final condition in rule.when) {
        // Null means the signal never resolved. Skip the rule rather than let
        // an absent value read as a failed comparison — the difference between
        // "you are under your protein target" and "you have not logged food".
        final result = condition.evaluate(context);
        if (result == null || !result) {
          matched = false;
          break;
        }
      }
      if (matched) fired.add(rule);
    }

    fired.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      // Ties break on id so the card does not reshuffle between rebuilds.
      return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
    });

    final seenDomains = <HerculDomain>{};
    final out = <HerculMessage>[];
    for (final rule in fired) {
      if (!seenDomains.add(rule.domain)) continue;
      out.add(
        HerculMessage(
          ruleId: rule.id,
          domain: rule.domain,
          priority: rule.priority,
          text: render(rule.copy[tone]!, context),
          cta: rule.cta,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  static bool _isCoolingDown(HerculRule rule, DateTime? last, DateTime now) {
    if (last == null || rule.cooldownDays <= 0) return false;
    return now.difference(last).inDays < rule.cooldownDays;
  }

  static bool _hasRequiredSignals(HerculRule rule, HerculContext context) {
    for (final condition in rule.when) {
      if (!context.has(condition.signal, condition.arg)) return false;
    }
    for (final signal in rule.requires) {
      // `requires` names a bare signal; an argument-keyed one is satisfied by
      // any subject, since the copy picks its own.
      if (!context.has(signal) && !context.series.containsKey(signal)) {
        return false;
      }
    }
    return true;
  }

  /// Substitutes `{signal}`, `{signal:arg}`, `{signal|fmt}` and
  /// `{signal:arg|fmt}` from [context].
  ///
  /// Formats: `int` (rounded), `1dp`, `pct` (0.78 → "78"), `kg` (one decimal
  /// plus unit), `abs` (magnitude, for phrasing a loss as a positive number).
  /// An unresolved placeholder renders as "—" rather than throwing: a rule is
  /// data, and a typo in one string should degrade that message, not crash the
  /// dashboard.
  static String render(String template, HerculContext context) {
    return template.replaceAllMapped(_placeholder, (match) {
      final signal = match.group(1)!;
      final arg = match.group(2);
      final format = match.group(3);

      final label = context.label(signal);
      if (label != null) return label;

      final value = context.number(signal, arg);
      if (value == null) return '—';
      return _format(value, format);
    });
  }

  static final _placeholder =
      RegExp(r'\{([a-zA-Z][\w.]*)(?::([^|}]+))?(?:\|(\w+))?\}');

  static String _format(double value, String? format) {
    switch (format) {
      case 'pct':
        return (value * 100).round().toString();
      case '1dp':
        return value.toStringAsFixed(1);
      case 'kg':
        return '${value.toStringAsFixed(1)} kg';
      case 'abs':
        return value.abs().toStringAsFixed(1);
      case 'int':
      default:
        return value.round().toString();
    }
  }
}
