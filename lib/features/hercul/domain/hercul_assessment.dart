import 'package:herculex/features/hercul/domain/hercul_context.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';

/// Four-tier glance rating for the Hercul Insights dashboard widget and report.
enum HerculGlanceStatus {
  great('great', 'Great'),
  good('good', 'Good'),
  notGood('not_good', 'Not Good'),
  bad('bad', 'Bad');

  const HerculGlanceStatus(this.id, this.label);
  final String id;
  final String label;
}

/// Logical cause-and-effect breakdown for one lifestyle or physiological factor
/// (Fasting, Alcohol, Creatine, Carbs Before Bed, Sodium/Hydration, Sleep/CNS).
class HerculFactorImpact {
  final String id;
  final String title;
  final String valueLabel;
  final HerculGlanceStatus status;
  final String weightImpactSummary;
  final String liftingImpactSummary;
  final String waterRetentionEffect;
  final String regenerationEffect;
  final bool isTracked;
  final String? route;

  const HerculFactorImpact({
    required this.id,
    required this.title,
    required this.valueLabel,
    required this.status,
    required this.weightImpactSummary,
    required this.liftingImpactSummary,
    required this.waterRetentionEffect,
    required this.regenerationEffect,
    required this.isTracked,
    this.route,
  });
}

/// Logical assessment of one core dimension:
/// Bodyweight Fluctuations, Lifting Load Fluctuations, Water Retention, or Regeneration.
class HerculDimensionAssessment {
  final String id;
  final String title;
  final HerculGlanceStatus status;
  final String metricBadge;
  final String headline;
  final String explanation;
  final List<String> keyDrivers;

  const HerculDimensionAssessment({
    required this.id,
    required this.title,
    required this.status,
    required this.metricBadge,
    required this.headline,
    required this.explanation,
    this.keyDrivers = const [],
  });
}

/// Complete Hercul Insights Report combining the 4-tier glance status,
/// logical cause-and-effect assessments for bodyweight & lifting fluctuations,
/// water retention & regeneration analysis, and all active fired rules.
class HerculInsightsReport {
  final HerculGlanceStatus overallStatus;
  final int overallScore;
  final String glanceHeadline;
  final String glanceSubtext;
  final HerculDimensionAssessment bodyweightAssessment;
  final HerculDimensionAssessment liftingAssessment;
  final HerculDimensionAssessment waterRetentionAssessment;
  final HerculDimensionAssessment regenerationAssessment;
  final List<HerculFactorImpact> factors;
  final List<HerculMessage> messages;

  const HerculInsightsReport({
    required this.overallStatus,
    required this.overallScore,
    required this.glanceHeadline,
    required this.glanceSubtext,
    required this.bodyweightAssessment,
    required this.liftingAssessment,
    required this.waterRetentionAssessment,
    required this.regenerationAssessment,
    required this.factors,
    required this.messages,
  });

  /// Classifies an individual [HerculMessage] into the 4-tier status scale.
  static HerculGlanceStatus classifyMessage(HerculMessage message) {
    final id = message.ruleId;
    if (_greatRuleIds.contains(id) ||
        id.contains('great') ||
        id.contains('surge') ||
        id.contains('strong') ||
        id.contains('on-point') ||
        id.contains('fresh-go-heavy') ||
        id.contains('deficit-progress') ||
        id.contains('recomp-success') ||
        id.contains('primed')) {
      return HerculGlanceStatus.great;
    }
    if (_goodRuleIds.contains(id) ||
        id.contains('reassurance') ||
        id.contains('intracellular-good') ||
        id.contains('glycogen-good') ||
        id.contains('water-drop-expected') ||
        id.contains('refeed-bounce') ||
        id.contains('advantage') ||
        message.domain == HerculDomain.ergonomics && message.priority <= 60) {
      return HerculGlanceStatus.good;
    }
    if (message.priority >= 83 ||
        id.contains('alcohol') ||
        id.contains('deload-due') ||
        id.contains('cns-high') ||
        id.contains('cut-too-fast') ||
        id.contains('training-lapsed') ||
        id.contains('crash') ||
        id.contains('wrecked')) {
      return HerculGlanceStatus.bad;
    }
    return HerculGlanceStatus.notGood;
  }

  static const _greatRuleIds = {
    'cns-fresh-go-heavy',
    'protein-on-point',
    'consistency-strong',
    'deficit-progress',
    'creatine-saturated-strength-up',
    'carbs-before-bed-strength-surge',
    'fasting-autophagy-recovery-great',
    'sleep-optimal-strength-surge',
    'recomp-weight-flat-strength-up',
    'hydration-optimal-performance',
    'creatine-and-late-carbs-peak-pump',
    'clean-recovery-no-alcohol-pr-window',
  };

  static const _goodRuleIds = {
    'scale-up-creatine-intracellular-good',
    'scale-up-late-carbs-glycogen-good',
    'scale-down-fasting-water-drop-expected',
    'fasting-refeed-scale-bounce',
    'short-lifter-conventional-advantage',
    'tall-squat-lowbar',
    'tall-sumo-lagging-squat',
    'tall-bench-long-arms',
    'ergo-long-femur-squat',
    'ergo-long-arms-bench',
  };

  /// Synthesizes a full [HerculInsightsReport] from [context] and [messages].
  static HerculInsightsReport build({
    required HerculContext context,
    required List<HerculMessage> messages,
  }) {
    // ── Extract signals ──
    final weight1d = context.number(HerculSignals.weightDeltaKg, '1');
    final weight3d = context.number(HerculSignals.weightDeltaKg, '3');
    final weight7d = context.number(HerculSignals.weightDeltaKg, '7');
    final weight14d = context.number(HerculSignals.weightDeltaKg, '14');
    final currentWeight = context.number(HerculSignals.weightKg);
    final goal = context.label(HerculSignals.goal);

    final lifting7dPct = context.number(HerculSignals.liftingDeltaPct7d);
    final lastLoadPct = context.number(HerculSignals.lastSessionLoadDeltaPct);
    final lastRpe = context.number(HerculSignals.lastSessionAvgRpe);
    final daysSinceWorkout = context.number(HerculSignals.daysSinceLastWorkout);

    final fastYesterdayH = context.number(HerculSignals.fastingYesterdayHours);
    final fastActiveH = context.number(HerculSignals.fastingActiveHours);
    final fastCompleted7d = context.number(HerculSignals.fastingCompleted7d);

    final alcoholYesterdayG = context.number(HerculSignals.alcoholYesterdayG);
    final alcoholDrinks = context.number(HerculSignals.alcoholYesterdayDrinks);
    final alcoholDays7d = context.number(HerculSignals.alcoholDays7d);

    final creatineYesterday = context.number(
      HerculSignals.creatineTakenYesterday,
    );
    final creatine7d = context.number(HerculSignals.creatineDays7d);
    final creatineLoading = context.number(HerculSignals.creatineLoadingPhase);

    final lateCarbsG = context.number(HerculSignals.carbsBeforeBedYesterdayG);
    final lateCarbsPct = context.number(
      HerculSignals.carbsBeforeBedPctYesterday,
    );
    final totalCarbsG = context.number(HerculSignals.carbsYesterdayG);
    final sodiumMg = context.number(HerculSignals.sodiumYesterdayMg);
    final waterMl = context.number(HerculSignals.waterYesterdayMl);
    final proteinPct7d = context.number(HerculSignals.proteinPct7d);

    final sleepYesterdayH = context.number(HerculSignals.sleepYesterdayHours);
    final cnsReadiness = context.number(HerculSignals.cnsReadiness);
    final cnsDeload = context.number(HerculSignals.cnsDeloadSuggested);
    final waterIndex = context.number(HerculSignals.waterRetentionIndex);
    final regenScoreRaw = context.number(HerculSignals.regenerationScore);

    // ── 1. Factor Impacts ──
    final factors = <HerculFactorImpact>[
      _buildFastingFactor(
        fastYesterdayH: fastYesterdayH,
        fastActiveH: fastActiveH,
        fastCompleted7d: fastCompleted7d,
      ),
      _buildAlcoholFactor(
        alcoholYesterdayG: alcoholYesterdayG,
        alcoholDrinks: alcoholDrinks,
        alcoholDays7d: alcoholDays7d,
      ),
      _buildCreatineFactor(
        creatineYesterday: creatineYesterday,
        creatine7d: creatine7d,
        creatineLoading: creatineLoading,
      ),
      _buildCarbsBeforeBedFactor(
        lateCarbsG: lateCarbsG,
        lateCarbsPct: lateCarbsPct,
        totalCarbsG: totalCarbsG,
      ),
      _buildHydrationSodiumFactor(sodiumMg: sodiumMg, waterMl: waterMl),
      _buildSleepCnsFactor(
        sleepYesterdayH: sleepYesterdayH,
        cnsReadiness: cnsReadiness,
        proteinPct7d: proteinPct7d,
      ),
    ];

    // ── 2. Dimension Assessments ──
    final bodyweightAssessment = _assessBodyweight(
      currentWeight: currentWeight,
      weight1d: weight1d,
      weight3d: weight3d,
      weight7d: weight7d,
      weight14d: weight14d,
      goal: goal,
      lateCarbsG: lateCarbsG,
      creatine7d: creatine7d,
      creatineLoading: creatineLoading,
      fastYesterdayH: fastYesterdayH,
      fastActiveH: fastActiveH,
      alcoholYesterdayG: alcoholYesterdayG,
      sodiumMg: sodiumMg,
    );

    final liftingAssessment = _assessLifting(
      lifting7dPct: lifting7dPct,
      lastLoadPct: lastLoadPct,
      lastRpe: lastRpe,
      daysSinceWorkout: daysSinceWorkout,
      lateCarbsG: lateCarbsG,
      creatine7d: creatine7d,
      fastYesterdayH: fastYesterdayH,
      fastActiveH: fastActiveH,
      alcoholYesterdayG: alcoholYesterdayG,
      sleepYesterdayH: sleepYesterdayH,
      cnsReadiness: cnsReadiness,
    );

    final waterRetentionAssessment = _assessWaterRetention(
      waterIndex: waterIndex,
      weight1d: weight1d,
      lateCarbsG: lateCarbsG,
      creatine7d: creatine7d,
      creatineLoading: creatineLoading,
      fastYesterdayH: fastYesterdayH,
      fastActiveH: fastActiveH,
      alcoholYesterdayG: alcoholYesterdayG,
      sodiumMg: sodiumMg,
      waterMl: waterMl,
    );

    final regenerationAssessment = _assessRegeneration(
      regenScoreRaw: regenScoreRaw,
      cnsReadiness: cnsReadiness,
      cnsDeload: cnsDeload,
      sleepYesterdayH: sleepYesterdayH,
      alcoholYesterdayG: alcoholYesterdayG,
      alcoholDays7d: alcoholDays7d,
      proteinPct7d: proteinPct7d,
      fastYesterdayH: fastYesterdayH,
    );

    // ── 3. Overall Score & Glance Status ──
    double score = regenScoreRaw ?? 76.0;

    // Incorporate dimension statuses
    final dimensions = [
      bodyweightAssessment.status,
      liftingAssessment.status,
      waterRetentionAssessment.status,
      regenerationAssessment.status,
    ];
    double dimSum = 0;
    for (final d in dimensions) {
      dimSum += switch (d) {
        HerculGlanceStatus.great => 90,
        HerculGlanceStatus.good => 76,
        HerculGlanceStatus.notGood => 54,
        HerculGlanceStatus.bad => 32,
      };
    }
    score = (score * 0.45) + ((dimSum / dimensions.length) * 0.55);

    // Adjust for fired rule severities
    int badCount = 0;
    int notGoodCount = 0;
    int greatCount = 0;
    for (final m in messages) {
      final s = classifyMessage(m);
      if (s == HerculGlanceStatus.bad) badCount++;
      if (s == HerculGlanceStatus.notGood) notGoodCount++;
      if (s == HerculGlanceStatus.great) greatCount++;
    }

    if (badCount >= 2 || (cnsDeload == 1 && (cnsReadiness ?? 1.0) < 0.35)) {
      score = score.clamp(15.0, 39.0);
    } else if (badCount == 1) {
      score = (score - 14.0).clamp(25.0, 58.0);
    } else if (notGoodCount >= 2) {
      score = (score - 8.0).clamp(42.0, 61.0);
    } else if (greatCount >= 1 && badCount == 0 && notGoodCount == 0) {
      score = (score + 8.0).clamp(80.0, 98.0);
    }

    final int finalScore = score.round().clamp(0, 100);
    final HerculGlanceStatus overallStatus;
    if (finalScore >= 80) {
      overallStatus = HerculGlanceStatus.great;
    } else if (finalScore >= 62) {
      overallStatus = HerculGlanceStatus.good;
    } else if (finalScore >= 42) {
      overallStatus = HerculGlanceStatus.notGood;
    } else {
      overallStatus = HerculGlanceStatus.bad;
    }

    final String glanceHeadline;
    if (messages.isNotEmpty) {
      glanceHeadline = messages.first.text;
    } else {
      glanceHeadline = switch (overallStatus) {
        HerculGlanceStatus.great =>
          'Physiology, recovery, and lifting progression are firing in sync.',
        HerculGlanceStatus.good =>
          'Bodyweight, water balance, and training load are well regulated.',
        HerculGlanceStatus.notGood =>
          'Recovery or fueling friction detected — tap to review physiological drivers.',
        HerculGlanceStatus.bad =>
          'High fatigue or recovery disruption detected — adjust today\'s training load.',
      };
    }

    final glanceParts = <String>[
      'Water: ${waterRetentionAssessment.metricBadge}',
      'Lifting: ${liftingAssessment.metricBadge}',
      'Regen: ${regenerationAssessment.metricBadge}',
    ];

    return HerculInsightsReport(
      overallStatus: overallStatus,
      overallScore: finalScore,
      glanceHeadline: glanceHeadline,
      glanceSubtext: glanceParts.join(' · '),
      bodyweightAssessment: bodyweightAssessment,
      liftingAssessment: liftingAssessment,
      waterRetentionAssessment: waterRetentionAssessment,
      regenerationAssessment: regenerationAssessment,
      factors: factors,
      messages: messages,
    );
  }

  static HerculFactorImpact _buildFastingFactor({
    required double? fastYesterdayH,
    required double? fastActiveH,
    required double? fastCompleted7d,
  }) {
    final activeH = fastActiveH ?? 0;
    final yestH = fastYesterdayH ?? 0;
    final effectiveH = activeH > yestH ? activeH : yestH;
    final tracked =
        fastYesterdayH != null ||
        (fastActiveH != null && fastActiveH > 0) ||
        (fastCompleted7d != null && fastCompleted7d > 0);

    if (!tracked) {
      return const HerculFactorImpact(
        id: 'fasting',
        title: 'Fasting State',
        valueLabel: 'No fasts logged',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'No active or recent fasts logged. Glycogen-bound water remains at normal fed baseline.',
        liftingImpactSummary:
            'Standard fed-state glycogen availability for resistance training.',
        waterRetentionEffect: 'Baseline glycogen water',
        regenerationEffect: 'Normal fed anabolism',
        isTracked: false,
        route: '/fasting',
      );
    }

    if (effectiveH >= 20) {
      return HerculFactorImpact(
        id: 'fasting',
        title: 'Fasting State',
        valueLabel: '${effectiveH.toStringAsFixed(1)}h fast',
        status: HerculGlanceStatus.notGood,
        weightImpactSummary:
            'A ${effectiveH.toStringAsFixed(0)}h fast depletes liver and muscle glycogen, flushing ~0.6–1.5 kg of bound water. Expect a sharp scale drop that rebounds upon refeeding.',
        liftingImpactSummary:
            'Deep fasting (>20h) reduces intramuscular glycogen and elevates cortisol; high-rep sets and total volume will feel heavier unless preceded by a pre-workout meal.',
        waterRetentionEffect: '-0.6 to -1.5 kg glycogen water drop',
        regenerationEffect: 'High autophagy · Delayed MPS until refeed',
        isTracked: true,
        route: '/fasting',
      );
    } else if (effectiveH >= 14) {
      return HerculFactorImpact(
        id: 'fasting',
        title: 'Fasting State',
        valueLabel: '${effectiveH.toStringAsFixed(1)}h IF window',
        status: HerculGlanceStatus.great,
        weightImpactSummary:
            '${effectiveH.toStringAsFixed(0)}h intermittent fast mildly lowers morning extracellular fluid (-0.3 to -0.6 kg) while keeping muscle glycogen intact.',
        liftingImpactSummary:
            'Catecholamine (noradrenaline) elevation during 14–18h fasts preserves top-set neural drive, provided post-workout protein & carbs are hit.',
        waterRetentionEffect: '-0.3 to -0.6 kg morning fluid flush',
        regenerationEffect: 'Insulin sensitivity + Autophagy boost',
        isTracked: true,
        route: '/fasting',
      );
    } else {
      return HerculFactorImpact(
        id: 'fasting',
        title: 'Fasting State',
        valueLabel:
            '${(fastCompleted7d ?? 0).round()} fasts / 7d (${effectiveH.toStringAsFixed(0)}h last)',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Short fasting window keeps glycogen stores steady with minimal scale water swing.',
        liftingImpactSummary:
            'Glycogen stores remain topped up for compound and hypertrophy work.',
        waterRetentionEffect: 'Stable fluid balance',
        regenerationEffect: 'Balanced feeding window',
        isTracked: true,
        route: '/fasting',
      );
    }
  }

  static HerculFactorImpact _buildAlcoholFactor({
    required double? alcoholYesterdayG,
    required double? alcoholDrinks,
    required double? alcoholDays7d,
  }) {
    final g = alcoholYesterdayG ?? 0;
    final drinks = alcoholDrinks ?? (g / 14.0);
    final days7d = (alcoholDays7d ?? 0).round();
    final tracked = alcoholYesterdayG != null || alcoholDays7d != null;

    if (!tracked || (g <= 0 && days7d == 0)) {
      return HerculFactorImpact(
        id: 'alcohol',
        title: 'Alcohol (Previous Day)',
        valueLabel: tracked ? '0 drinks (Clean)' : 'None logged',
        status: HerculGlanceStatus.great,
        weightImpactSummary:
            'Zero alcohol yesterday: no ADH diuretic dehydration or next-day cortisol water rebound.',
        liftingImpactSummary:
            'Unimpaired CNS motor unit recruitment and full myofibrillar protein synthesis.',
        waterRetentionEffect: 'Zero cortisol water rebound',
        regenerationEffect: '100% MPS & REM sleep preserved',
        isTracked: tracked,
        route: '/app',
      );
    }

    if (g >= 28 || drinks >= 2.0) {
      return HerculFactorImpact(
        id: 'alcohol',
        title: 'Alcohol (Previous Day)',
        valueLabel:
            '${drinks.toStringAsFixed(1)} drinks (${g.round()}g ethanol)',
        status: HerculGlanceStatus.bad,
        weightImpactSummary:
            'Alcohol suppresses vasopressin (ADH) causing an initial dehydration dip, followed 12–36h later by aldosterone/cortisol rebound that holds +0.5–1.5 kg extracellular water while pausing fat oxidation.',
        liftingImpactSummary:
            'Yesterday\'s alcohol blunts CNS readiness, fragments REM/deep sleep, and reduces muscle protein synthesis by ~20–30%. Expect working weights to feel 5–10% heavier (higher RPE).',
        waterRetentionEffect: 'Dehydration dip → +0.5–1.5 kg cortisol bloat',
        regenerationEffect: '-24% MPS · Suppressed CNS & HRV',
        isTracked: true,
        route: '/app',
      );
    } else if (g > 0) {
      return HerculFactorImpact(
        id: 'alcohol',
        title: 'Alcohol (Previous Day)',
        valueLabel: '${drinks.toStringAsFixed(1)} drink (${g.round()}g)',
        status: HerculGlanceStatus.notGood,
        weightImpactSummary:
            'Light alcohol intake yesterday causes mild fluid shifts (+0.2–0.5 kg water fluctuation) and briefly prioritizes hepatic acetate clearance over fat burning.',
        liftingImpactSummary:
            'Minor impact on neural drive; add 500 ml water + electrolytes before lifting.',
        waterRetentionEffect: 'Mild transient fluid shift',
        regenerationEffect: 'Slight REM sleep reduction',
        isTracked: true,
        route: '/app',
      );
    } else {
      return HerculFactorImpact(
        id: 'alcohol',
        title: 'Alcohol (Previous Day)',
        valueLabel: '0 yesterday ($days7d days in 7d)',
        status: days7d >= 3
            ? HerculGlanceStatus.notGood
            : HerculGlanceStatus.good,
        weightImpactSummary:
            'No alcohol yesterday, though $days7d drinking days this week can cause lingering extracellular water fluctuations.',
        liftingImpactSummary:
            'Acute CNS impact has cleared, but cumulative weekly recovery is slightly blunted.',
        waterRetentionEffect: 'Stabilizing post-alcohol fluid',
        regenerationEffect: days7d >= 3
            ? 'Cumulative recovery drag'
            : 'Recovering normally',
        isTracked: true,
        route: '/app',
      );
    }
  }

  static HerculFactorImpact _buildCreatineFactor({
    required double? creatineYesterday,
    required double? creatine7d,
    required double? creatineLoading,
  }) {
    if (creatine7d == null && creatineYesterday == null) {
      return const HerculFactorImpact(
        id: 'creatine',
        title: 'Creatine Intake',
        valueLabel: 'Not configured',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Add Creatine to your Supplements Tracker so Hercul can separate intracellular muscle hydration (+1–2 kg) from fat gain.',
        liftingImpactSummary:
            '5g daily creatine monohydrate saturates phosphocreatine (PCr) stores, boosting heavy 3–12 rep output by 3–8%.',
        waterRetentionEffect: 'Untracked intracellular H₂O',
        regenerationEffect: 'Add to Supplements to track',
        isTracked: false,
        route: '/supplements',
      );
    }

    final days = (creatine7d ?? 0).round();
    final takenYest = (creatineYesterday ?? 0) >= 1;
    final loading = (creatineLoading ?? 0) >= 1;

    if (loading) {
      return HerculFactorImpact(
        id: 'creatine',
        title: 'Creatine Intake',
        valueLabel: '$days/7 days (Loading / Saturating)',
        status: HerculGlanceStatus.great,
        weightImpactSummary:
            'Recent creatine uptake pulls +0.8 to +2.0 kg of water directly inside muscle cells (sarcoplasm). If the scale jumped, this is beneficial lean cell volume — not fat.',
        liftingImpactSummary:
            'Rising intramuscular phosphocreatine buffers ATP during heavy sets, adding 1–2 reps and improving bar speed.',
        waterRetentionEffect: '+0.8 to +2.0 kg intracellular muscle H₂O',
        regenerationEffect: 'Cellular swelling → Anabolic signaling',
        isTracked: true,
        route: '/supplements',
      );
    } else if (days >= 5) {
      return HerculFactorImpact(
        id: 'creatine',
        title: 'Creatine Intake',
        valueLabel: '$days/7 days (Saturated)',
        status: HerculGlanceStatus.great,
        weightImpactSummary:
            'Consistent creatine ($days/7d) maintains stable intracellular muscle hydration (+1.0–1.8 kg baseline lean mass water).',
        liftingImpactSummary:
            'Full phosphocreatine saturation supports peak force output on heavy compounds and faster inter-set recovery.',
        waterRetentionEffect: 'Optimal intracellular hydration',
        regenerationEffect: 'Peak ATP resynthesis & cell volume',
        isTracked: true,
        route: '/supplements',
      );
    } else if (days >= 2 || takenYest) {
      return HerculFactorImpact(
        id: 'creatine',
        title: 'Creatine Intake',
        valueLabel: '$days/7 days (Partial)',
        status: HerculGlanceStatus.notGood,
        weightImpactSummary:
            'Inconsistent creatine ($days/7d) causes intracellular muscle water to fluctuate by 0.4–0.9 kg across the week.',
        liftingImpactSummary:
            'Sub-optimal PCr saturation leaves 1–2 reps on the table on high-intensity sets.',
        waterRetentionEffect: 'Fluctuating intracellular water',
        regenerationEffect: 'Partial PCr resynthesis',
        isTracked: true,
        route: '/supplements',
      );
    } else {
      return HerculFactorImpact(
        id: 'creatine',
        title: 'Creatine Intake',
        valueLabel: '$days/7 days (Missed)',
        status: HerculGlanceStatus.notGood,
        weightImpactSummary:
            'Skipped creatine over the past week gradually releases 0.5–1.5 kg of intracellular muscle water, making muscles look flatter and lowering scale weight.',
        liftingImpactSummary:
            'Depleting creatine stores reduces explosive power and rep endurance on sets of 5–12.',
        waterRetentionEffect: '-0.5 to -1.5 kg intracellular water loss',
        regenerationEffect: 'Slower ATP regeneration between sets',
        isTracked: true,
        route: '/supplements',
      );
    }
  }

  static HerculFactorImpact _buildCarbsBeforeBedFactor({
    required double? lateCarbsG,
    required double? lateCarbsPct,
    required double? totalCarbsG,
  }) {
    if (lateCarbsG == null && totalCarbsG == null) {
      return const HerculFactorImpact(
        id: 'carbs_before_bed',
        title: 'Carbs Before Bed',
        valueLabel: 'No evening meals logged',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Log dinner and evening snacks so Hercul can calculate overnight glycogen water binding (~3g H₂O per 1g carb).',
        liftingImpactSummary:
            'Evening carbohydrates stock muscle glycogen for next-day training sessions.',
        waterRetentionEffect: 'Awaiting dinner/snack log',
        regenerationEffect: 'Awaiting evening nutrition log',
        isTracked: false,
        route: '/app',
      );
    }

    final lateG = lateCarbsG ?? 0;
    final pct = ((lateCarbsPct ?? 0) * 100).round();

    if (lateG >= 90) {
      final boundWaterKg = (lateG * 3.0) / 1000.0;
      return HerculFactorImpact(
        id: 'carbs_before_bed',
        title: 'Carbs Before Bed',
        valueLabel: '${lateG.round()}g late carbs ($pct% of day)',
        status: HerculGlanceStatus.great,
        weightImpactSummary:
            '${lateG.round()}g of evening carbs binds ~${boundWaterKg.toStringAsFixed(1)} kg of intracellular water with muscle glycogen overnight. An upward scale tick this morning is glycogen fuel, not fat.',
        liftingImpactSummary:
            'Supercompensated muscle glycogen increases muscle leverage, pump, and work capacity — ideal day to push working weights or reps.',
        waterRetentionEffect:
            '+${boundWaterKg.toStringAsFixed(1)} kg glycogen-bound muscle H₂O',
        regenerationEffect: 'Lowered overnight cortisol + Full glycogen',
        isTracked: true,
        route: '/app',
      );
    } else if (lateG >= 35) {
      return HerculFactorImpact(
        id: 'carbs_before_bed',
        title: 'Carbs Before Bed',
        valueLabel: '${lateG.round()}g late carbs',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Moderate evening carbs (${lateG.round()}g) replenish muscle glycogen without causing an oversized morning scale jump.',
        liftingImpactSummary:
            'Balanced muscle glycogen availability for today\'s working sets.',
        waterRetentionEffect: 'Balanced overnight glycogen hydration',
        regenerationEffect: 'Steady overnight recovery & serotonin support',
        isTracked: true,
        route: '/app',
      );
    } else {
      return HerculFactorImpact(
        id: 'carbs_before_bed',
        title: 'Carbs Before Bed',
        valueLabel: '${lateG.round()}g late carbs (Low)',
        status: (totalCarbsG ?? 0) < 100
            ? HerculGlanceStatus.notGood
            : HerculGlanceStatus.good,
        weightImpactSummary:
            'Low evening carbs (${lateG.round()}g) and lower total carbs (${(totalCarbsG ?? 0).round()}g) leave glycogen stores lighter, dropping morning scale water by 0.3–0.8 kg.',
        liftingImpactSummary:
            'With minimal evening carb loading, muscles may feel flatter and 8–15 rep hypertrophy sets may fatigue 1–2 reps earlier.',
        waterRetentionEffect: '-0.3 to -0.8 kg lower glycogen water',
        regenerationEffect: 'Lighter glycogen replenishment overnight',
        isTracked: true,
        route: '/app',
      );
    }
  }

  static HerculFactorImpact _buildHydrationSodiumFactor({
    required double? sodiumMg,
    required double? waterMl,
  }) {
    final tracked = sodiumMg != null || (waterMl != null && waterMl > 0);
    if (!tracked) {
      return const HerculFactorImpact(
        id: 'hydration_sodium',
        title: 'Sodium & Hydration',
        valueLabel: 'Not logged yesterday',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Sodium and water intake govern extracellular fluid balance and acute day-to-day scale swings.',
        liftingImpactSummary:
            'Proper sodium + water maintains blood plasma volume and intramuscular pump.',
        waterRetentionEffect: 'Untracked sodium/water',
        regenerationEffect: 'Log meals & water to track',
        isTracked: false,
        route: '/nutrient-overview',
      );
    }

    final na = sodiumMg ?? 0;
    final h2o = waterMl ?? 0;

    if (na >= 3500) {
      return HerculFactorImpact(
        id: 'hydration_sodium',
        title: 'Sodium & Hydration',
        valueLabel: '${na.round()} mg Na · ${h2o.round()} ml H₂O',
        status: h2o >= 2500
            ? HerculGlanceStatus.good
            : HerculGlanceStatus.notGood,
        weightImpactSummary:
            'High sodium yesterday (${na.round()} mg) transiently increases extracellular osmolarity, holding +0.4–1.2 kg of water for 24–48h.',
        liftingImpactSummary:
            'Elevated sodium expands plasma volume and joint cushioning — expect strong pumps and better leverage on presses and squats.',
        waterRetentionEffect: '+0.4 to +1.2 kg extracellular sodium water',
        regenerationEffect: h2o >= 2500
            ? 'High plasma volume'
            : 'Needs water to flush excess Na',
        isTracked: true,
        route: '/nutrient-overview',
      );
    } else {
      return HerculFactorImpact(
        id: 'hydration_sodium',
        title: 'Sodium & Hydration',
        valueLabel:
            '${na > 0 ? "${na.round()} mg Na" : ""}${na > 0 && h2o > 0 ? " · " : ""}${h2o > 0 ? "${h2o.round()} ml H₂O" : "Logged"}',
        status: h2o >= 2000 || na > 0
            ? HerculGlanceStatus.good
            : HerculGlanceStatus.notGood,
        weightImpactSummary:
            'Sodium intake is within normal physiological range — minimal extracellular bloat.',
        liftingImpactSummary:
            'Steady electrolyte balance for neuromuscular contraction.',
        waterRetentionEffect: 'Normal extracellular balance',
        regenerationEffect: 'Balanced cellular hydration',
        isTracked: true,
        route: '/nutrient-overview',
      );
    }
  }

  static HerculFactorImpact _buildSleepCnsFactor({
    required double? sleepYesterdayH,
    required double? cnsReadiness,
    required double? proteinPct7d,
  }) {
    final tracked =
        sleepYesterdayH != null || cnsReadiness != null || proteinPct7d != null;
    if (!tracked) {
      return const HerculFactorImpact(
        id: 'sleep_cns',
        title: 'Sleep, CNS & Protein',
        valueLabel: 'Awaiting telemetry',
        status: HerculGlanceStatus.good,
        weightImpactSummary:
            'Sleep debt elevates morning cortisol, which can mask fat loss via extracellular water retention.',
        liftingImpactSummary:
            'CNS readiness and sleep depth govern bar velocity and 1RM force output.',
        waterRetentionEffect: 'Baseline cortisol',
        regenerationEffect: 'Awaiting sleep & workout logs',
        isTracked: false,
        route: '/cns',
      );
    }

    final sleep = sleepYesterdayH;
    final cnsPct = cnsReadiness != null ? (cnsReadiness * 100).round() : null;
    final protPct = proteinPct7d != null ? (proteinPct7d * 100).round() : null;

    final parts = <String>[
      if (sleep != null) '${sleep.toStringAsFixed(1)}h sleep',
      if (cnsPct != null) '$cnsPct% CNS',
      if (protPct != null) '$protPct% protein',
    ];

    final isBad =
        (sleep != null && sleep < 5.5) || (cnsReadiness ?? 1.0) < 0.35;
    final isNotGood =
        (sleep != null && sleep < 6.5) ||
        (cnsReadiness ?? 1.0) < 0.55 ||
        (proteinPct7d ?? 1.0) < 0.82;
    final isGreat =
        (sleep == null || sleep >= 7.2) &&
        (cnsReadiness == null || cnsReadiness >= 0.65) &&
        (proteinPct7d == null || proteinPct7d >= 0.92);

    final status = isBad
        ? HerculGlanceStatus.bad
        : isNotGood
        ? HerculGlanceStatus.notGood
        : isGreat
        ? HerculGlanceStatus.great
        : HerculGlanceStatus.good;

    return HerculFactorImpact(
      id: 'sleep_cns',
      title: 'Sleep, CNS & Protein',
      valueLabel: parts.join(' · '),
      status: status,
      weightImpactSummary: (sleep != null && sleep < 6.0)
          ? 'Under-sleeping (${sleep.toStringAsFixed(1)}h) spikes morning cortisol, causing temporary extracellular water retention that masks true tissue weight.'
          : 'Rested cortisol profile allows true tissue weight to show cleanly on the scale.',
      liftingImpactSummary: isBad || isNotGood
          ? 'Elevated CNS fatigue or sleep debt increases perceived RPE by +0.5–1.5 at the same bar weight.'
          : 'High CNS readiness and protein coverage support progressive overload on top sets.',
      waterRetentionEffect: (sleep != null && sleep < 6.0)
          ? 'Sleep-debt cortisol retention'
          : 'Low cortisol fluid retention',
      regenerationEffect: status == HerculGlanceStatus.great
          ? 'Peak myofibrillar & neural repair'
          : status == HerculGlanceStatus.good
          ? 'Solid daily regeneration'
          : 'Impaired neural / tissue repair',
      isTracked: true,
      route: '/cns',
    );
  }

  static HerculDimensionAssessment _assessBodyweight({
    required double? currentWeight,
    required double? weight1d,
    required double? weight3d,
    required double? weight7d,
    required double? weight14d,
    required String? goal,
    required double? lateCarbsG,
    required double? creatine7d,
    required double? creatineLoading,
    required double? fastYesterdayH,
    required double? fastActiveH,
    required double? alcoholYesterdayG,
    required double? sodiumMg,
  }) {
    final shortDelta = weight1d ?? weight3d ?? weight7d;
    if (currentWeight == null && shortDelta == null && weight14d == null) {
      return const HerculDimensionAssessment(
        id: 'bodyweight',
        title: 'Bodyweight Fluctuation Analysis',
        status: HerculGlanceStatus.good,
        metricBadge: 'Log weight',
        headline: 'Log daily bodyweight to unlock fluctuation attribution.',
        explanation:
            'Hercul correlates your daily scale weight against carbs before bed, creatine saturation, fasting duration, and alcohol intake to distinguish water shifts from real tissue changes.',
      );
    }

    final drivers = <String>[];
    final d1 = weight1d ?? weight3d ?? 0.0;

    final badgeParts = <String>[
      if (currentWeight != null) '${currentWeight.toStringAsFixed(1)} kg',
      if (shortDelta != null)
        '${shortDelta >= 0 ? "+" : ""}${shortDelta.toStringAsFixed(1)} kg recent',
      if (weight14d != null)
        '${weight14d >= 0 ? "+" : ""}${weight14d.toStringAsFixed(1)} kg (14d)',
    ];
    final badge = badgeParts.isEmpty ? 'Tracked' : badgeParts.join(' · ');

    // Case 1: Scale jumped up, explained by late carbs / creatine / sodium / alcohol
    if (d1 >= 0.4) {
      final causes = <String>[];
      var isBeneficialWater = false;
      var isCortisolWater = false;

      if ((lateCarbsG ?? 0) >= 75) {
        causes.add(
          '${lateCarbsG!.round()}g carbs before bed (~${((lateCarbsG * 3) / 1000).toStringAsFixed(1)} kg glycogen-bound intracellular water)',
        );
        drivers.add('Late Carbs Glycogen (+H₂O)');
        isBeneficialWater = true;
      }
      if ((creatineLoading ?? 0) >= 1 || (creatine7d ?? 0) >= 5) {
        causes.add('creatine intracellular muscle hydration');
        drivers.add('Creatine Saturation');
        isBeneficialWater = true;
      }
      if ((sodiumMg ?? 0) >= 3200) {
        causes.add('${sodiumMg!.round()} mg sodium extracellular fluid');
        drivers.add('High Sodium Osmolarity');
      }
      if ((alcoholYesterdayG ?? 0) >= 14) {
        causes.add('post-alcohol cortisol/aldosterone water rebound');
        drivers.add('Alcohol Rebound Bloat');
        isCortisolWater = true;
      }

      if (causes.isNotEmpty) {
        final status = isCortisolWater
            ? HerculGlanceStatus.notGood
            : isBeneficialWater
            ? HerculGlanceStatus.great
            : HerculGlanceStatus.good;
        return HerculDimensionAssessment(
          id: 'bodyweight',
          title: 'Bodyweight Fluctuation Analysis',
          status: status,
          metricBadge: badge,
          headline: isCortisolWater
              ? 'Scale up +${d1.toStringAsFixed(1)} kg from post-alcohol / sodium fluid retention.'
              : 'Scale up +${d1.toStringAsFixed(1)} kg is intracellular muscle water & glycogen — not fat.',
          explanation:
              'Your scale rose +${d1.toStringAsFixed(1)} kg, logically driven by ${causes.join(", ")}. '
              '${isBeneficialWater ? "Intracellular water sits inside the muscle belly, improving leverage and force production today." : "This extracellular water shift will clear within 24–48h of normal hydration."}',
          keyDrivers: drivers,
        );
      }
    }

    // Case 2: Scale dropped sharply, explained by fasting / low carbs / acute alcohol diuresis
    if (d1 <= -0.4) {
      final fastH = (fastActiveH ?? 0) > (fastYesterdayH ?? 0)
          ? (fastActiveH ?? 0)
          : (fastYesterdayH ?? 0);
      final causes = <String>[];
      if (fastH >= 15) {
        causes.add('${fastH.toStringAsFixed(0)}h fasting glycogen/fluid flush');
        drivers.add('${fastH.toStringAsFixed(0)}h Fast Depletion');
      }
      if (lateCarbsG != null && lateCarbsG < 30) {
        causes.add('low evening carbs (${lateCarbsG.round()}g)');
        drivers.add('Low Evening Carbs');
      }
      if ((alcoholYesterdayG ?? 0) >= 20) {
        causes.add('acute alcohol diuretic dehydration');
        drivers.add('Alcohol Dehydration');
      }

      if (causes.isNotEmpty) {
        return HerculDimensionAssessment(
          id: 'bodyweight',
          title: 'Bodyweight Fluctuation Analysis',
          status: (alcoholYesterdayG ?? 0) >= 20
              ? HerculGlanceStatus.notGood
              : HerculGlanceStatus.good,
          metricBadge: badge,
          headline:
              'Scale down ${d1.toStringAsFixed(1)} kg — driven by ${causes.first}.',
          explanation:
              'The ${d1.toStringAsFixed(1)} kg drop reflects ${causes.join(" and ")}. '
              'Expect 0.4–1.0 kg to return naturally when muscle glycogen and hydration normalize — do not mistake the refeed bounce for fat gain.',
          keyDrivers: drivers,
        );
      }
    }

    // Case 3: Evaluate 14-day trend against goal
    if (goal == 'weightLoss' && weight14d != null) {
      if (weight14d < -2.5) {
        return HerculDimensionAssessment(
          id: 'bodyweight',
          title: 'Bodyweight Fluctuation Analysis',
          status: HerculGlanceStatus.bad,
          metricBadge: badge,
          headline:
              'Down ${weight14d.abs().toStringAsFixed(1)} kg in 14 days — pace risks lean tissue loss.',
          explanation:
              'Even accounting for glycogen water, losing ${weight14d.abs().toStringAsFixed(1)} kg over two weeks is aggressive and threatens lifting strength and muscle retention.',
          keyDrivers: const ['Rapid Deficit', 'Glycogen Depletion'],
        );
      } else if (weight14d <= -0.4) {
        return HerculDimensionAssessment(
          id: 'bodyweight',
          title: 'Bodyweight Fluctuation Analysis',
          status: HerculGlanceStatus.great,
          metricBadge: badge,
          headline:
              'Down ${weight14d.abs().toStringAsFixed(1)} kg in 14 days — controlled fat-loss pace.',
          explanation:
              'Your 14-day bodyweight trend (${weight14d.toStringAsFixed(1)} kg) is in the ideal zone for losing fat while preserving strength and intracellular muscle mass.',
          keyDrivers: const ['Controlled Cut Pace'],
        );
      }
    }

    return HerculDimensionAssessment(
      id: 'bodyweight',
      title: 'Bodyweight Fluctuation Analysis',
      status: HerculGlanceStatus.good,
      metricBadge: badge,
      headline:
          'Bodyweight is stable with no abnormal water spikes or crash drops.',
      explanation:
          'Recent scale readings ($badge) align with steady hydration and glycogen turnover.',
      keyDrivers: drivers.isEmpty ? const ['Stable Baseline'] : drivers,
    );
  }

  static HerculDimensionAssessment _assessLifting({
    required double? lifting7dPct,
    required double? lastLoadPct,
    required double? lastRpe,
    required double? daysSinceWorkout,
    required double? lateCarbsG,
    required double? creatine7d,
    required double? fastYesterdayH,
    required double? fastActiveH,
    required double? alcoholYesterdayG,
    required double? sleepYesterdayH,
    required double? cnsReadiness,
  }) {
    final deltaPct = lifting7dPct ?? lastLoadPct;
    if (deltaPct == null && daysSinceWorkout == null) {
      return const HerculDimensionAssessment(
        id: 'lifting',
        title: 'Lifting Weight & Strength Analysis',
        status: HerculGlanceStatus.good,
        metricBadge: 'Log sets',
        headline: 'Log workouts to correlate lifting loads with lifestyle.',
        explanation:
            'Hercul compares your working weights and estimated 1RMs against fasting windows, evening carb loading, creatine saturation, sleep, and alcohol.',
      );
    }

    final pctStr = deltaPct != null
        ? '${deltaPct >= 0 ? "+" : ""}${deltaPct.toStringAsFixed(1)}% load'
        : 'Logged';
    final rpeStr = lastRpe != null
        ? ' · RPE ${lastRpe.toStringAsFixed(1)}'
        : '';
    final badge = '$pctStr$rpeStr';

    final boosters = <String>[];
    final drags = <String>[];

    if ((lateCarbsG ?? 0) >= 75) {
      boosters.add('${lateCarbsG!.round()}g evening carbs (topped glycogen)');
    } else if (lateCarbsG != null && lateCarbsG < 25) {
      drags.add('low evening carbs (${lateCarbsG.round()}g)');
    }

    if ((creatine7d ?? 0) >= 5) {
      boosters.add('saturated creatine (${creatine7d!.round()}/7d)');
    } else if (creatine7d != null && creatine7d <= 2) {
      drags.add('missed creatine (${creatine7d.round()}/7d)');
    }

    final fastH = (fastActiveH ?? 0) > (fastYesterdayH ?? 0)
        ? (fastActiveH ?? 0)
        : (fastYesterdayH ?? 0);
    if (fastH >= 18) {
      drags.add('${fastH.toStringAsFixed(0)}h fasted glycogen depletion');
    }

    if ((alcoholYesterdayG ?? 0) >= 14) {
      drags.add('previous-day alcohol (${alcoholYesterdayG!.round()}g)');
    }

    if (sleepYesterdayH != null && sleepYesterdayH < 6.2) {
      drags.add('${sleepYesterdayH.toStringAsFixed(1)}h sleep debt');
    } else if (sleepYesterdayH != null && sleepYesterdayH >= 7.5) {
      boosters.add('${sleepYesterdayH.toStringAsFixed(1)}h restorative sleep');
    }

    if (cnsReadiness != null && cnsReadiness < 0.45) {
      drags.add(
        'high CNS fatigue (${(cnsReadiness * 100).round()}% readiness)',
      );
    } else if (cnsReadiness != null && cnsReadiness >= 0.7) {
      boosters.add('fresh CNS (${(cnsReadiness * 100).round()}% readiness)');
    }

    // Lifting weight UP
    if ((deltaPct ?? 0) >= 1.5) {
      final why = boosters.isNotEmpty
          ? 'supported by ${boosters.join(", ")}'
          : 'confirming strong progressive overload adaptation';
      return HerculDimensionAssessment(
        id: 'lifting',
        title: 'Lifting Weight & Strength Analysis',
        status: HerculGlanceStatus.great,
        metricBadge: badge,
        headline:
            'Lifting loads are UP +${deltaPct!.toStringAsFixed(1)}% vs baseline.',
        explanation:
            'Your working weights and estimated 1RM rose +${deltaPct.toStringAsFixed(1)}%, logically $why. '
            'Intramuscular hydration and neural readiness are translating directly into bar weight.',
        keyDrivers: boosters.isEmpty
            ? const ['Progressive Overload']
            : boosters,
      );
    }

    // Lifting weight DOWN
    if ((deltaPct ?? 0) <= -2.0) {
      final hasPhysiologicalExcuse = drags.isNotEmpty;
      return HerculDimensionAssessment(
        id: 'lifting',
        title: 'Lifting Weight & Strength Analysis',
        status: (deltaPct! <= -5.0 || (alcoholYesterdayG ?? 0) >= 28)
            ? HerculGlanceStatus.bad
            : HerculGlanceStatus.notGood,
        metricBadge: badge,
        headline: hasPhysiologicalExcuse
            ? 'Lifting loads dipped ${deltaPct.toStringAsFixed(1)}% — explained by ${drags.first}.'
            : 'Lifting loads dipped ${deltaPct.toStringAsFixed(1)}% — monitor recovery and fueling.',
        explanation: hasPhysiologicalExcuse
            ? 'Your working weights dropped ${deltaPct.toStringAsFixed(1)}% due to acute physiological drag: ${drags.join(", ")}. '
                  'This is temporary performance masking (glycogen/CNS/hydration), NOT true strength or muscle loss. Do not overhaul your program — fix the fueling/recovery inputs.'
            : 'Working weights are down ${deltaPct.toStringAsFixed(1)}%. Check pre-workout carbohydrates, creatine consistency, and inter-session recovery.',
        keyDrivers: drags,
      );
    }

    // Stable lifting weight, check today's readiness/drags
    if (drags.length >= 2 || (alcoholYesterdayG ?? 0) >= 28) {
      return HerculDimensionAssessment(
        id: 'lifting',
        title: 'Lifting Weight & Strength Analysis',
        status: HerculGlanceStatus.notGood,
        metricBadge: badge,
        headline:
            'Strength baseline steady, but today carries ${drags.first} drag.',
        explanation:
            'While your 7-day lifting trend is steady ($badge), active factors (${drags.join(", ")}) mean the bar may feel heavier today. Autoregulate by RPE rather than forcing a 1RM.',
        keyDrivers: drags,
      );
    }

    return HerculDimensionAssessment(
      id: 'lifting',
      title: 'Lifting Weight & Strength Analysis',
      status: boosters.length >= 2
          ? HerculGlanceStatus.great
          : HerculGlanceStatus.good,
      metricBadge: badge,
      headline: boosters.isNotEmpty
          ? 'Lifting output steady ($pctStr) with ${boosters.first} priming today\'s session.'
          : 'Lifting loads are holding steady ($pctStr) across recent sessions.',
      explanation: boosters.isNotEmpty
          ? 'With ${boosters.join(" and ")}, your intramuscular energy systems are primed to push an extra rep or +1.25–2.5 kg on your main lifts.'
          : 'Consistent force production across recent sessions with controlled RPE.',
      keyDrivers: boosters.isNotEmpty ? boosters : const ['Steady Output'],
    );
  }

  static HerculDimensionAssessment _assessWaterRetention({
    required double? waterIndex,
    required double? weight1d,
    required double? lateCarbsG,
    required double? creatine7d,
    required double? creatineLoading,
    required double? fastYesterdayH,
    required double? fastActiveH,
    required double? alcoholYesterdayG,
    required double? sodiumMg,
    required double? waterMl,
  }) {
    final idx = waterIndex ?? 0.0;
    final hasCre = (creatine7d ?? 0) >= 4 || (creatineLoading ?? 0) >= 1;
    final hasLateCarbs = (lateCarbsG ?? 0) >= 75;
    final hasAlcohol = (alcoholYesterdayG ?? 0) >= 14;
    final hasHighSodium = (sodiumMg ?? 0) >= 3200;
    final fastH = (fastActiveH ?? 0) > (fastYesterdayH ?? 0)
        ? (fastActiveH ?? 0)
        : (fastYesterdayH ?? 0);

    // Post-alcohol / sodium extracellular retention
    if (hasAlcohol || (hasHighSodium && (waterMl ?? 0) < 2200)) {
      return HerculDimensionAssessment(
        id: 'water_retention',
        title: 'Water Retention & Fluid Compartment',
        status: hasAlcohol
            ? HerculGlanceStatus.bad
            : HerculGlanceStatus.notGood,
        metricBadge: 'Extracellular +H₂O',
        headline: hasAlcohol
            ? 'Post-alcohol cortisol & aldosterone rebound is holding extracellular water.'
            : 'High sodium with low water intake is causing transient extracellular retention.',
        explanation:
            'Not all water weight is equal: alcohol and unbuffered sodium push fluid into the extracellular space (under the skin), softening muscle definition without helping strength. Drink 2.5–3.5L of water and eat potassium-rich foods to flush it within 24–48h.',
        keyDrivers: [
          if (hasAlcohol) 'Alcohol Cortisol Rebound',
          if (hasHighSodium) 'High Sodium (${sodiumMg!.round()} mg)',
        ],
      );
    }

    // Beneficial Intracellular Hydration (Creatine + Late Carbs)
    if (hasCre || hasLateCarbs) {
      final sources = <String>[
        if (hasCre) 'Creatine (${(creatine7d ?? 0).round()}/7d)',
        if (hasLateCarbs) 'Late Carbs (${lateCarbsG!.round()}g)',
      ];
      return HerculDimensionAssessment(
        id: 'water_retention',
        title: 'Water Retention & Fluid Compartment',
        status: HerculGlanceStatus.great,
        metricBadge: 'Intracellular Optimal',
        headline:
            'Beneficial intracellular muscle hydration from ${sources.join(" & ")}.',
        explanation:
            'Each gram of muscle glycogen binds ~3g of water inside the muscle fiber, and creatine osmotically draws fluid into the sarcoplasm. Even if scale weight is +0.5 to +1.8 kg higher, this is intracellular muscle fullness that protects joints and increases pressing/squatting leverage.',
        keyDrivers: sources,
      );
    }

    // Glycogen / Fasting Depletion
    if (fastH >= 16 || idx <= -25) {
      return HerculDimensionAssessment(
        id: 'water_retention',
        title: 'Water Retention & Fluid Compartment',
        status: HerculGlanceStatus.good,
        metricBadge: 'Glycogen Depleted',
        headline:
            'Low fluid retention following ${fastH >= 16 ? "${fastH.toStringAsFixed(0)}h fast" : "low carb / glycogen turnover"}.',
        explanation:
            'Fasting lowers insulin and depletes liver/muscle glycogen, releasing bound water and sodium via the kidneys. Your current scale weight sits at the bottom of your hydration band.',
        keyDrivers: [
          if (fastH >= 16) '${fastH.toStringAsFixed(0)}h Fast Flush',
          'Low Insulin Natriuresis',
        ],
      );
    }

    return const HerculDimensionAssessment(
      id: 'water_retention',
      title: 'Water Retention & Fluid Compartment',
      status: HerculGlanceStatus.good,
      metricBadge: 'Balanced H₂O',
      headline: 'Intra- and extracellular fluid compartments are balanced.',
      explanation:
          'No acute sodium spikes, alcohol rebound, or deep glycogen depletion skewing today\'s scale reading.',
      keyDrivers: ['Normohydrated'],
    );
  }

  static HerculDimensionAssessment _assessRegeneration({
    required double? regenScoreRaw,
    required double? cnsReadiness,
    required double? cnsDeload,
    required double? sleepYesterdayH,
    required double? alcoholYesterdayG,
    required double? alcoholDays7d,
    required double? proteinPct7d,
    required double? fastYesterdayH,
  }) {
    final score = (regenScoreRaw ?? 76.0).round().clamp(0, 100);
    final status = score >= 80
        ? HerculGlanceStatus.great
        : score >= 62
        ? HerculGlanceStatus.good
        : score >= 42
        ? HerculGlanceStatus.notGood
        : HerculGlanceStatus.bad;

    final positives = <String>[];
    final negatives = <String>[];

    if (cnsDeload == 1) {
      negatives.add('CNS Deload Indicated');
    } else if ((cnsReadiness ?? 0.7) >= 0.65) {
      positives.add('CNS Fresh (${((cnsReadiness ?? 0.7) * 100).round()}%)');
    } else if ((cnsReadiness ?? 0.7) < 0.45) {
      negatives.add('High CNS Fatigue');
    }

    if ((sleepYesterdayH ?? 7.5) >= 7.2) {
      if (sleepYesterdayH != null) {
        positives.add('${sleepYesterdayH.toStringAsFixed(1)}h Sleep');
      }
    } else if (sleepYesterdayH != null && sleepYesterdayH < 6.2) {
      negatives.add('${sleepYesterdayH.toStringAsFixed(1)}h Short Sleep');
    }

    if ((alcoholYesterdayG ?? 0) >= 14) {
      negatives.add('Alcohol MPS Suppression');
    } else if ((alcoholDays7d ?? 0) >= 3) {
      negatives.add('${alcoholDays7d!.round()}d Weekly Alcohol');
    }

    if ((proteinPct7d ?? 0.9) >= 0.9) {
      if (proteinPct7d != null) {
        positives.add('${(proteinPct7d * 100).round()}% Protein Target');
      }
    } else if (proteinPct7d != null && proteinPct7d < 0.82) {
      negatives.add('Low Protein (${(proteinPct7d * 100).round()}%)');
    }

    if ((fastYesterdayH ?? 0) >= 22) {
      negatives.add('Extended Fast Recovery Delay');
    }

    final headline = switch (status) {
      HerculGlanceStatus.great =>
        'Regeneration at $score% — systemic, neural, and muscular recovery are optimal.',
      HerculGlanceStatus.good =>
        'Regeneration at $score% — ready for normal programmed training volume.',
      HerculGlanceStatus.notGood =>
        'Regeneration at $score% — ${negatives.isNotEmpty ? negatives.first : "accumulated fatigue"} is slowing tissue repair.',
      HerculGlanceStatus.bad =>
        'Regeneration compromised ($score%) — ${negatives.isNotEmpty ? negatives.join(" + ") : "deload or active recovery needed"}.',
    };

    final explanation = negatives.isNotEmpty
        ? 'Regeneration is held back by ${negatives.join(", ")}. '
              '${positives.isNotEmpty ? "Positive buffers: ${positives.join(", ")}. " : ""}'
              'Prioritize sleep, hydration, and hitting your daily protein target before pushing failure sets.'
        : 'Central nervous system readiness, muscle group recovery, and protein availability are aligned for high-output training and hypertrophy.';

    return HerculDimensionAssessment(
      id: 'regeneration',
      title: 'Systemic & Muscular Regeneration',
      status: status,
      metricBadge: '$score% Regen',
      headline: headline,
      explanation: explanation,
      keyDrivers: [...negatives, ...positives],
    );
  }
}
