import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/hercul/domain/hercul_context.dart';
import 'package:herculex/features/hercul/domain/hercul_engine.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';

final _now = DateTime(2026, 8, 18, 9);

HerculContext _context({
  Map<String, double> scalars = const {},
  Map<String, SignalSeries> series = const {},
  Map<String, String> labels = const {},
}) =>
    HerculContext(
      scalars: scalars,
      series: series,
      labels: labels,
      now: _now,
    );

HerculRule _rule(
  String id, {
  required List<HerculCondition> when,
  int priority = 50,
  int cooldownDays = 0,
  HerculDomain domain = HerculDomain.consistency,
  List<String> requires = const [],
  String normal = 'normal copy',
  String honest = 'honest copy',
}) =>
    HerculRule(
      id: id,
      domain: domain,
      priority: priority,
      cooldownDays: cooldownDays,
      requires: requires,
      when: when,
      copy: {HerculTone.normal: normal, HerculTone.honest: honest},
    );

void main() {
  group('condition evaluation', () {
    test('a missing signal is null, not false', () {
      const condition = HerculCondition(
        signal: HerculSignals.proteinPct7d,
        op: ConditionOp.lt,
        value: 0.85,
      );
      expect(condition.evaluate(_context()), isNull);
      expect(
        condition.evaluate(
          _context(scalars: {HerculSignals.proteinPct7d: 0.7}),
        ),
        isTrue,
      );
    });

    test('between is inclusive at both ends', () {
      const condition = HerculCondition(
        signal: HerculSignals.cnsLoad,
        op: ConditionOp.between,
        value: 0.4,
        upper: 0.7,
      );
      for (final (load, expected) in [
        (0.39, false),
        (0.4, true),
        (0.55, true),
        (0.7, true),
        (0.71, false),
      ]) {
        expect(
          condition.evaluate(_context(scalars: {HerculSignals.cnsLoad: load})),
          expected,
          reason: 'load $load',
        );
      }
    });

    test('label conditions compare text, and ordering them is not satisfied',
        () {
      const eq = HerculCondition(
        signal: HerculSignals.goal,
        op: ConditionOp.eq,
        text: 'weightLoss',
      );
      expect(
        eq.evaluate(_context(labels: {HerculSignals.goal: 'weightLoss'})),
        isTrue,
      );
      expect(
        eq.evaluate(_context(labels: {HerculSignals.goal: 'muscleGain'})),
        isFalse,
      );

      const gt = HerculCondition(
        signal: HerculSignals.goal,
        op: ConditionOp.gt,
        text: 'weightLoss',
      );
      expect(
        gt.evaluate(_context(labels: {HerculSignals.goal: 'weightLoss'})),
        isFalse,
      );
    });

    test('argument-keyed signals resolve per subject', () {
      const condition = HerculCondition(
        signal: HerculSignals.weeklySets,
        arg: 'Rear Delts',
        op: ConditionOp.lt,
        value: 6,
      );
      final context = _context(series: {
        HerculSignals.weeklySets: {'Rear Delts': 3, 'Chest': 14},
      });
      expect(condition.evaluate(context), isTrue);
      expect(
        const HerculCondition(
          signal: HerculSignals.weeklySets,
          arg: 'Chest',
          op: ConditionOp.lt,
          value: 6,
        ).evaluate(context),
        isFalse,
      );
      // A subject that was never resolved is unknown, not zero.
      expect(
        const HerculCondition(
          signal: HerculSignals.weeklySets,
          arg: 'Calves',
          op: ConditionOp.lt,
          value: 6,
        ).evaluate(context),
        isNull,
      );
    });
  });

  group('evaluate', () {
    test('a rule whose signals are absent is skipped, not fired', () {
      // The fresh-install case: no food logged, so "under your protein target"
      // must not fire.
      final rules = [
        _rule(
          'protein',
          when: [
            const HerculCondition(
              signal: HerculSignals.proteinPct7d,
              op: ConditionOp.lt,
              value: 0.85,
            ),
          ],
        ),
      ];
      expect(
        HerculEngine.evaluate(context: _context(), rules: rules),
        isEmpty,
      );
    });

    test('requires gates a signal the copy needs but the conditions do not', () {
      final rules = [
        _rule(
          'needs-height',
          requires: [HerculSignals.heightCm],
          when: [
            const HerculCondition(
              signal: HerculSignals.cnsLoad,
              op: ConditionOp.gt,
              value: 0.1,
            ),
          ],
        ),
      ];
      final withoutHeight = _context(scalars: {HerculSignals.cnsLoad: 0.9});
      expect(
        HerculEngine.evaluate(context: withoutHeight, rules: rules),
        isEmpty,
      );

      final withHeight = _context(
        scalars: {HerculSignals.cnsLoad: 0.9, HerculSignals.heightCm: 190},
      );
      expect(
        HerculEngine.evaluate(context: withHeight, rules: rules),
        hasLength(1),
      );
    });

    test('a rule inside its cooldown stays quiet', () {
      final rules = [
        _rule(
          'squat',
          cooldownDays: 10,
          when: [
            const HerculCondition(
              signal: HerculSignals.daysSinceLastWorkout,
              op: ConditionOp.gte,
              value: 1,
            ),
          ],
        ),
      ];
      final context =
          _context(scalars: {HerculSignals.daysSinceLastWorkout: 3});

      expect(HerculEngine.evaluate(context: context, rules: rules), hasLength(1));
      expect(
        HerculEngine.evaluate(
          context: context,
          rules: rules,
          lastFiredAt: {'squat': _now.subtract(const Duration(days: 4))},
        ),
        isEmpty,
      );
      expect(
        HerculEngine.evaluate(
          context: context,
          rules: rules,
          lastFiredAt: {'squat': _now.subtract(const Duration(days: 11))},
        ),
        hasLength(1),
      );
    });

    test('messages rank by priority and at most one per domain survives', () {
      final always = [
        const HerculCondition(
          signal: HerculSignals.cnsLoad,
          op: ConditionOp.gte,
          value: 0,
        ),
      ];
      final rules = [
        _rule('low', priority: 10, domain: HerculDomain.volume, when: always),
        _rule('high', priority: 90, domain: HerculDomain.volume, when: always),
        _rule('mid', priority: 50, domain: HerculDomain.nutrition, when: always),
      ];
      final out = HerculEngine.evaluate(
        context: _context(scalars: {HerculSignals.cnsLoad: 0.5}),
        rules: rules,
      );
      expect(out.map((m) => m.ruleId), ['high', 'mid']);
    });

    test('ordering is deterministic when priorities tie', () {
      final always = [
        const HerculCondition(
          signal: HerculSignals.cnsLoad,
          op: ConditionOp.gte,
          value: 0,
        ),
      ];
      final rules = [
        _rule('zulu', priority: 50, domain: HerculDomain.volume, when: always),
        _rule('alpha', priority: 50, domain: HerculDomain.nutrition, when: always),
      ];
      final context = _context(scalars: {HerculSignals.cnsLoad: 0.5});
      final first = HerculEngine.evaluate(context: context, rules: rules);
      final second = HerculEngine.evaluate(context: context, rules: rules);
      expect(first.map((m) => m.ruleId), ['alpha', 'zulu']);
      expect(second.map((m) => m.ruleId), first.map((m) => m.ruleId));
    });

    test('tone selects the copy', () {
      final rules = [
        _rule(
          'tone',
          normal: 'polite',
          honest: 'blunt',
          when: [
            const HerculCondition(
              signal: HerculSignals.cnsLoad,
              op: ConditionOp.gte,
              value: 0,
            ),
          ],
        ),
      ];
      final context = _context(scalars: {HerculSignals.cnsLoad: 0.1});
      expect(
        HerculEngine.evaluate(context: context, rules: rules).single.text,
        'polite',
      );
      expect(
        HerculEngine.evaluate(
          context: context,
          rules: rules,
          tone: HerculTone.honest,
        ).single.text,
        'blunt',
      );
    });
  });

  group('render', () {
    final context = _context(
      scalars: {
        HerculSignals.heightCm: 190,
        HerculSignals.proteinPct7d: 0.78,
        HerculSignals.cnsAcwr: 1.63,
      },
      series: {
        HerculSignals.weeklySets: {'Chest': 14, 'Rear Delts': 3},
        HerculSignals.weightDeltaKg: {'21': -0.2},
      },
      labels: {HerculSignals.goal: 'weightLoss'},
    );

    test('resolves scalars, arguments, labels and formats', () {
      expect(HerculEngine.render('{profile.heightCm|int} cm', context),
          '190 cm');
      expect(HerculEngine.render('{nutrition.proteinPct7d|pct}%', context),
          '78%');
      expect(HerculEngine.render('{cns.acwr|1dp}x', context), '1.6x');
      expect(
        HerculEngine.render('{volume.weeklySets:Rear Delts|int} sets', context),
        '3 sets',
      );
      expect(HerculEngine.render('{profile.goal}', context), 'weightLoss');
    });

    test('abs states a loss as a magnitude, so copy can supply the direction',
        () {
      expect(
        HerculEngine.render('{body.weightDeltaKg:21|abs} kg', context),
        '0.2 kg',
      );
    });

    test('an argument may itself contain a colon', () {
      // `exercise.e1rmRatio` is keyed "slugA:slugB", so the arg group has to
      // swallow the second colon rather than stopping at it.
      final ratios = _context(
        series: {
          HerculSignals.e1rmRatio: {'sumo-deadlift:barbell-back-squat': 1.04},
        },
      );
      expect(
        HerculEngine.render(
          '{exercise.e1rmRatio:sumo-deadlift:barbell-back-squat|1dp}x',
          ratios,
        ),
        '1.0x',
      );
    });

    test('an unresolved placeholder degrades to a dash rather than throwing',
        () {
      // A rule is data; a typo in one string must not take down the dashboard.
      expect(HerculEngine.render('{nutrition.kcalPct7d|pct}%', context), '—%');
    });
  });

  group('shipped corpus', () {
    late List<Map<String, dynamic>> raw;
    late List<HerculRule> rules;

    setUpAll(() {
      raw = (jsonDecode(
        File('assets/data/hercul_rules.json').readAsStringSync(),
      ) as List)
          .cast<Map<String, dynamic>>();
      rules = raw.map(HerculRule.fromJson).toList();
    });

    test('every rule parses and ids are unique', () {
      expect(rules, isNotEmpty);
      final ids = rules.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate rule ids');
    });

    test('every rule authors both tones', () {
      // Enforced here as well as in the parser: a rule missing `honest` would
      // silently speak in the polite voice to a user who asked for the other.
      for (final rule in rules) {
        for (final tone in HerculTone.values) {
          expect(
            rule.copy[tone]?.trim(),
            isNotEmpty,
            reason: '${rule.id} has no ${tone.id} copy',
          );
        }
      }
    });

    test('the two tones are actually different text', () {
      final identical = [
        for (final r in rules)
          if (r.copy[HerculTone.normal] == r.copy[HerculTone.honest]) r.id,
      ];
      expect(identical, isEmpty);
    });

    test('every referenced signal exists in the vocabulary', () {
      // The corpus is data, so nothing else catches `nutrition.protienPct7d`
      // before it silently never fires.
      final unknown = <String>{};
      for (final rule in rules) {
        for (final signal in rule.referencedSignals) {
          if (!HerculSignals.all.contains(signal)) unknown.add(signal);
        }
      }
      expect(unknown, isEmpty, reason: 'unknown signals: $unknown');
    });

    test('argument-keyed signals are given an argument, and vice versa', () {
      final problems = <String>[];
      for (final rule in rules) {
        for (final c in rule.when) {
          final needsArg = HerculSignals.argumentSignals.contains(c.signal);
          if (needsArg && c.arg == null) {
            problems.add('${rule.id}: ${c.signal} needs an arg');
          }
          if (!needsArg && c.arg != null) {
            problems.add('${rule.id}: ${c.signal} takes no arg');
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('label signals are compared with text and numerics with values', () {
      final problems = <String>[];
      for (final rule in rules) {
        for (final c in rule.when) {
          final isLabel = HerculSignals.labelSignals.contains(c.signal);
          if (isLabel && c.text == null) {
            problems.add('${rule.id}: ${c.signal} must compare against text');
          }
          if (!isLabel && c.text != null) {
            problems.add('${rule.id}: ${c.signal} is numeric');
          }
          if (c.op == ConditionOp.between && c.upper == null) {
            problems.add('${rule.id}: between needs an upper bound');
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('every placeholder in both tones resolves against the vocabulary', () {
      final placeholder =
          RegExp(r'\{([a-zA-Z][\w.]*)(?::([^|}]+))?(?:\|(\w+))?\}');
      final problems = <String>[];
      for (final rule in rules) {
        for (final tone in HerculTone.values) {
          for (final m in placeholder.allMatches(rule.copy[tone]!)) {
            final signal = m.group(1)!;
            if (!HerculSignals.all.contains(signal)) {
              problems.add('${rule.id}/${tone.id}: unknown "$signal"');
              continue;
            }
            final needsArg = HerculSignals.argumentSignals.contains(signal);
            if (needsArg && m.group(2) == null) {
              problems.add('${rule.id}/${tone.id}: "$signal" needs an arg');
            }
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('priorities and cooldowns are in range', () {
      for (final rule in rules) {
        expect(rule.priority, inInclusiveRange(0, 100), reason: rule.id);
        expect(rule.cooldownDays, inInclusiveRange(0, 90), reason: rule.id);
      }
    });

    test('an empty context fires nothing at all', () {
      // A fresh install has no training, food or bodyweight history. Hercul
      // must have nothing to say rather than something wrong to say.
      expect(
        HerculEngine.evaluate(context: _context(), rules: rules),
        isEmpty,
      );
    });

    test('the worked example fires with the copy it was written for', () {
      final context = _context(
        series: {
          HerculSignals.weeklySets: {'Chest': 14, 'Rear Delts': 3},
        },
      );
      final out = HerculEngine.evaluate(
        context: context,
        rules: rules,
        tone: HerculTone.honest,
      );
      final message = out.firstWhere((m) => m.ruleId == 'rear-delts-neglected');
      expect(message.text, contains('14 sets of chest'));
      expect(message.text, contains('3 of rear delts'));
      expect(message.text, isNot(contains('{')));
    });

    test('the honest voice never targets the body or sex', () {
      // The tone brief: blunt about training, never about the person. This is
      // the guard that keeps a future rule from crossing that line quietly.
      final banned = RegExp(
        r'\b(fat|fatty|obese|skinny|weak|pathetic|useless|lazy|'
        r'pussy|bastard|idiot|stupid|disgusting|ugly)\b',
        caseSensitive: false,
      );
      final offenders = <String>[];
      for (final rule in rules) {
        for (final tone in HerculTone.values) {
          final hit = banned.firstMatch(rule.copy[tone]!);
          if (hit != null) offenders.add('${rule.id}/${tone.id}: ${hit[0]}');
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
