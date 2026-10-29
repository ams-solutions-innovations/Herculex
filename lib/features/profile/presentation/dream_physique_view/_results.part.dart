part of '../dream_physique_view.dart';

extension _DreamPhysiqueResults on _DreamPhysiqueViewState {
  Widget _buildResultsView(DreamPhysiqueAnalysisResult r, Profile? profile) {
    final hx = context.hx;
    final timeframe = _splitTimeframe(r.timeframeRange);
    final now = DateTime.now();
    final readyBy = DateTime(now.year, now.month + r.estimatedMonths);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resultsHero(r),
        const SizedBox(height: 22),
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _shortAesthetic(r.targetAestheticStyle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: hx.primaryText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Text(
              'Target aesthetic',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: hx.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _DpEyebrow('REALISTIC TIMEFRAME', spacing: 1.6),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeframe.$1,
                style: _dpDisplay(
                  76,
                  weight: FontWeight.w600,
                  letterSpacing: -3.5,
                  height: 1,
                ),
              ),
              if (timeframe.$2.isNotEmpty) ...[
                const SizedBox(width: HxSpace.x2),
                Text(
                  timeframe.$2,
                  style: _dpDisplay(
                    24,
                    weight: FontWeight.w600,
                    color: hx.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text:
                'A conservative estimate from your photos and profile. '
                'Ready around ',
            children: [
              TextSpan(
                text: DateFormat('MMMM y').format(readyBy),
                style: TextStyle(
                  color: hx.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: hx.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _bodyFatPath(r),
        const SizedBox(height: 10),
        _changeStats(r, profile),
        const SizedBox(height: 28),
        _DpSectionTitle(
          'Where to focus',
          trailing: r.programmingProfile == null
              ? null
              : 'AI confidence '
                    '${(r.programmingProfile!.overallConfidence * 100).round()}%',
        ),
        const SizedBox(height: HxSpace.x1),
        Text(
          r.programmingProfile == null
              ? 'From an older analysis. Nothing in your program changes.'
              : 'Tap a level to change it. Nothing in your program changes '
                    'until you save.',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: hx.secondary,
          ),
        ),
        const SizedBox(height: HxSpace.x3),
        ..._focusCards(r),
        const SizedBox(height: 28),
        const _DpSectionTitle('Your plan'),
        const SizedBox(height: HxSpace.x3),
        _nutritionCard(r, profile),
        const SizedBox(height: HxSpace.x2),
        _trainingCard(r),
        const SizedBox(height: HxSpace.x2),
        _assessmentCard(r),
        const SizedBox(height: HxSpace.x3),
        Center(
          child: TextButton.icon(
            key: const Key('dream-physique-new-analysis'),
            onPressed: _startOver,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('New analysis'),
            style: TextButton.styleFrom(
              foregroundColor: hx.secondary,
              minimumSize: const Size(double.infinity, 46),
              textStyle: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Today's photo and the goal photo split down the middle.
  Widget _resultsHero(DreamPhysiqueAnalysisResult r) {
    final hx = context.hx;
    // Labels sit on a dark scrim over the photos in every theme, so the goal
    // accent uses the vivid fill in light themes instead of the dark text tint.
    final goalAccent = hx.brightness == Brightness.dark
        ? hx.primaryText
        : hx.primary;
    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: hx.outlineVariant),
        color: hx.surfaceContainerLowest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(
                  child: _DpPhoto(
                    _currentFiles.isEmpty ? null : _currentFiles.first,
                  ),
                ),
                Expanded(
                  child: _DpPhoto(
                    _targetFile,
                    placeholderIcon: Icons.star_rounded,
                  ),
                ),
              ],
            ),
            Center(child: Container(width: 2, color: Colors.white)),
            Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 22,
                  color: Color(0xFF0B1220),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: _heroLabel(
                'NOW',
                '~${r.currentEstimatedBf.round()}% BF',
                const Color(0xFFCBD5E1),
                Colors.white,
                CrossAxisAlignment.start,
              ),
            ),
            Positioned(
              right: 14,
              bottom: 12,
              child: _heroLabel(
                'GOAL',
                '~${r.targetBfPercent.round()}% BF',
                goalAccent,
                goalAccent,
                CrossAxisAlignment.end,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroLabel(
    String eyebrow,
    String value,
    Color eyebrowColor,
    Color valueColor,
    CrossAxisAlignment align,
  ) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          eyebrow,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: eyebrowColor,
          ),
        ),
        Text(value, style: _dpDisplay(22, color: valueColor)),
      ],
    );
  }

  /// The body-fat scale with today's range and the goal marked on it.
  Widget _bodyFatPath(DreamPhysiqueAnalysisResult r) {
    final hx = context.hx;
    final current = r.currentEstimatedBf;
    final target = r.targetBfPercent;
    final nowMin = r.currentBfRangeMin ?? current - 1;
    final nowMax = r.currentBfRangeMax ?? current + 1;
    final lo = math.min(6.0, (target - 2).floorToDouble());
    final hi = math.max(25.0, (nowMax + 3).ceilToDouble());
    double frac(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    final gap = current - target;
    final nowLabel = r.currentBfRangeMin != null && r.currentBfRangeMax != null
        ? '${nowMin.round()}–${nowMax.round()}%'
        : '~${current.round()}%';

    return Container(
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: _dpCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _DpEyebrow('BODY FAT PATH')),
              _DpEyebrow(
                '${gap >= 0 ? '−' : '+'}${gap.abs().toStringAsFixed(0)} pts',
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              Widget label(double at, String text, Color color) {
                const width = 72.0;
                final left = (frac(at) * w - width / 2).clamp(0.0, w - width);
                return Positioned(
                  left: left,
                  width: width,
                  top: 0,
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: _dpDisplay(14, color: color),
                  ),
                );
              }

              final nowLeft = frac(nowMin) * w;
              final nowWidth = math.max(18.0, frac(nowMax) * w - nowLeft);
              return SizedBox(
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    label((nowMin + nowMax) / 2, nowLabel, hx.onSurface),
                    label(target, '${target.round()}%', hx.primaryText),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 30,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: [hx.success, hx.primary, hx.outline],
                            stops: const [0, 0.4, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: nowLeft.clamp(0.0, w - nowWidth),
                      width: nowWidth,
                      top: 26,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: hx.onSurface.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: hx.onSurface, width: 1.5),
                        ),
                      ),
                    ),
                    Positioned(
                      left: frac(target) * w - 11,
                      top: 24,
                      width: 22,
                      height: 22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: hx.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: hx.background, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: hx.tertiary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${lo.round()}%'),
                Text('${((lo + hi) / 2).round()}%'),
                Text('${hi.round()}%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeStats(DreamPhysiqueAnalysisResult r, Profile? profile) {
    final hx = context.hx;
    final weight = profile?.weightKg;
    String signed(double v) =>
        '${v < 0 ? '−' : '+'}${v.abs().toStringAsFixed(1)} kg';

    Widget cell(String label, String value, Color? color, String sub) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: hx.secondary,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: _dpDisplay(22, weight: FontWeight.w600, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: hx.tertiary,
              ),
            ),
          ],
        ),
      );
    }

    final divider = BoxDecoration(
      border: Border(left: BorderSide(color: hx.outlineVariant)),
    );
    return Container(
      decoration: _dpCard(context, radius: 22),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: cell(
                'WEIGHT',
                signed(r.weightChangeKg),
                null,
                weight == null
                    ? (r.weightChangeKg <= 0 ? 'net loss' : 'net gain')
                    : '${_kg(weight)} → ${_kg(weight + r.weightChangeKg)}',
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: divider,
                child: cell(
                  'MUSCLE',
                  signed(r.leanMuscleGainKg),
                  hx.success,
                  'lean mass',
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: divider,
                child: cell('FAT', signed(-r.fatLossKg), hx.warning, 'to lose'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _focusCards(DreamPhysiqueAnalysisResult r) {
    final cards = <Widget>[];
    if (r.programmingProfile != null) {
      if (_reviewedProgrammingPriorities.isEmpty) {
        cards.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _dpCard(context, radius: 20),
            child: const Text(
              'No AI priorities. Run a new analysis or choose priorities '
              'manually later.',
            ),
          ),
        );
      }
      for (var i = 0; i < _reviewedProgrammingPriorities.length; i++) {
        final p = _reviewedProgrammingPriorities[i];
        cards.add(
          _focusCard(
            key: ValueKey('programming-priority-${p.muscleId}'),
            name: _muscleLabel(p.muscleId),
            focus: p.rationale,
            level: p.priority,
            onPick: (level) => _setPriority(i, level),
          ),
        );
      }
    } else {
      for (final p in r.musclePriorities) {
        cards.add(
          _focusCard(
            name: p.group,
            focus: p.focus,
            level: ProgrammingPriorityLevel.fromWire(p.priority),
          ),
        );
      }
    }
    return [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: HxSpace.x2),
        cards[i],
      ],
    ];
  }

  Color _levelColor(ProgrammingPriorityLevel level) => switch (level) {
    ProgrammingPriorityLevel.high => context.hx.primary,
    // The design's cyan "medium" is the fasting accent in every theme.
    ProgrammingPriorityLevel.medium => context.hx.domainFasting,
    ProgrammingPriorityLevel.maintenance => context.hx.tertiary,
  };

  Widget _focusCard({
    Key? key,
    required String name,
    required String focus,
    required ProgrammingPriorityLevel level,
    ValueChanged<ProgrammingPriorityLevel>? onPick,
  }) {
    final hx = context.hx;
    const levels = {
      ProgrammingPriorityLevel.high: 'High',
      ProgrammingPriorityLevel.medium: 'Medium',
      ProgrammingPriorityLevel.maintenance: 'Maintain',
    };
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: _dpCard(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: HxMotion.base,
                width: 6,
                height: 30,
                decoration: BoxDecoration(
                  color: _levelColor(level),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      focus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: hx.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: hx.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final entry in levels.entries) ...[
                  if (entry.key != ProgrammingPriorityLevel.high)
                    const SizedBox(width: 3),
                  Expanded(
                    child: _levelSegment(
                      entry.value,
                      entry.key,
                      selected: entry.key == level,
                      onTap: onPick == null ? null : () => onPick(entry.key),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelSegment(
    String label,
    ProgrammingPriorityLevel level, {
    required bool selected,
    VoidCallback? onTap,
  }) {
    final color = _levelColor(level);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF04121A);
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: HxMotion.fast,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: selected ? onColor : context.hx.secondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _nutritionCard(DreamPhysiqueAnalysisResult r, Profile? profile) {
    final hx = context.hx;
    final targets = ref.watch(baselineTargetsProvider);
    final weight = profile?.weightKg;
    final phase = weight == null
        ? null
        : PhysiqueDirectionRule.decide(
            weightKg: weight,
            currentBfPercent: r.currentEstimatedBf,
            targetBfPercent: r.targetBfPercent,
            plannedWeightChangeKg: r.weightChangeKg,
            prefersWeightLoss: profile?.goal == FitnessGoal.weightLoss,
          )?.phase;

    return Container(
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hx.success.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              hx.success.withValues(alpha: 0.12),
              hx.surfaceContainerLowest,
            ),
            hx.surfaceContainerLowest,
          ],
          stops: const [0, 0.55],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DpEyebrow(
            phase == null
                ? 'NUTRITION'
                : 'NUTRITION · ${phase.label.toUpperCase()} PHASE',
            icon: Icons.restaurant_rounded,
            color: hx.success,
          ),
          if (targets != null) ...[
            const SizedBox(height: HxSpace.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  NumberFormat.decimalPattern().format(targets.kcal),
                  style: _dpDisplay(
                    38,
                    weight: FontWeight.w600,
                    letterSpacing: -1.2,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'kcal / day · current target',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: hx.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HxSpace.x3),
            _macroBar(targets),
          ],
          const SizedBox(height: HxSpace.x3),
          Text(
            r.nutritionStrategy,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: hx.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _DpSecondaryButton(
            key: const Key('edit-nutrition-targets-from-dream-physique'),
            label: 'Update nutrition targets',
            color: hx.success,
            filled: false,
            onPressed: _openNutritionTargets,
          ),
        ],
      ),
    );
  }

  Widget _macroBar(MacroTargets t) {
    final hx = context.hx;
    final segments = [
      ('P', t.proteinG, t.proteinG * 4, hx.macroProtein, hx.macroProtein),
      ('C', t.carbsG, t.carbsG * 4, hx.macroCarbs, hx.macroCarbs),
      ('F', t.fatG, t.fatG * 9, hx.macroFat, hx.macroFatText),
    ];
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: math.max(1, segments[i].$3),
                    child: ColoredBox(color: segments[i].$4),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final s in segments)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: s.$1,
                      style: TextStyle(
                        color: s.$5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(text: ' ${s.$2} g'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: hx.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _trainingCard(DreamPhysiqueAnalysisResult r) {
    final hx = context.hx;
    final items = _adviceItems(r.trainingAdvice);
    return Container(
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: _dpCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DpEyebrow(
            'TRAINING',
            icon: Icons.fitness_center_rounded,
            color: hx.primaryText,
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: HxSpace.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    style: _dpDisplay(13.5, color: hx.primaryText),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    items[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: hx.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _assessmentCard(DreamPhysiqueAnalysisResult r) {
    final hx = context.hx;
    final limits = r.programmingProfile?.uncertainties ?? const <String>[];
    final body = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.55,
      color: hx.onSurfaceVariant,
    );
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('dream-physique-assessment'),
        onTap: _toggleAssessment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: AnimatedSize(
            duration: HxMotion.base,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: hx.secondary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Assessment & limitations',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _assessmentOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 22,
                      color: hx.secondary,
                    ),
                  ],
                ),
                if (_assessmentOpen) ...[
                  const SizedBox(height: HxSpace.x2),
                  Text(r.overallAssessment, style: body),
                  const SizedBox(height: HxSpace.x2),
                  Text(
                    'Target aesthetic: ${r.targetAestheticStyle}',
                    style: body,
                  ),
                  for (final item in limits) ...[
                    const SizedBox(height: HxSpace.x1),
                    Text('• $item', style: body),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    final hasPriorities =
        _result?.programmingProfile != null &&
        _reviewedProgrammingPriorities.isNotEmpty;
    return _DpPrimaryButton(
      key: const Key('confirm-dream-physique-programming-profile'),
      label: _saved
          ? (hasPriorities ? 'Priorities saved' : 'Goal saved')
          : _saving
          ? 'Saving…'
          : (hasPriorities ? 'Save goal & priorities' : 'Save goal'),
      icon: _saved ? Icons.check_circle_rounded : Icons.flag_rounded,
      busy: _saving && !_saved,
      success: _saved,
      onPressed: _saving || _saved ? null : _saveGoalAndPriorities,
    );
  }
}

String _kg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "9 - 12 months" → ("9–12", "months"); anything else stays whole.
(String, String) _splitTimeframe(String range) {
  final match = RegExp(
    r'^\s*(~?\s*\d+(?:[.,]\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?)\s*(.*)$',
  ).firstMatch(range);
  if (match == null) return (range.trim(), '');
  final number = match.group(1)!.replaceAll(RegExp(r'\s*[-–]\s*'), '–');
  return (number.replaceAll(' ', ''), match.group(2)!.trim());
}

/// "Athletic, defined V-taper physique…" → "ATHLETIC" for the chip; the full
/// phrase is kept under "Assessment & limitations".
String _shortAesthetic(String style) {
  final first = style.split(RegExp(r'[,;.(]')).first.trim();
  final words = first.split(RegExp(r'\s+'));
  final short = words.length > 3 ? words.take(3).join(' ') : first;
  return (short.isEmpty ? style : short).toUpperCase();
}

/// Breaks the AI's training advice into steps: by line when it already has
/// them, otherwise by sentence.
List<String> _adviceItems(String text) {
  final lines = text
      .split(RegExp(r'\n+'))
      .map(
        (l) => l.replaceFirst(RegExp(r'^\s*(?:[-•*]|\d+[.)])\s*'), '').trim(),
      )
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length > 1) return lines;
  final sentences = text
      .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return sentences.isEmpty ? [text] : sentences;
}

String _muscleLabel(String muscleId) {
  const labels = <String, String>{
    'chest': 'Chest',
    'back': 'Back',
    'lats': 'Lats',
    'traps': 'Traps',
    'front_delts': 'Front delts',
    'side_delts': 'Side delts',
    'rear_delts': 'Rear delts',
    'biceps': 'Biceps',
    'triceps': 'Triceps',
    'forearms': 'Forearms',
    'abs': 'Abs',
    'obliques': 'Obliques',
    'neck': 'Neck',
    'quads': 'Quads',
    'hamstrings': 'Hamstrings',
    'glutes': 'Glutes',
    'calves': 'Calves',
    'adductors': 'Adductors',
    'abductors': 'Abductors',
  };
  return labels[muscleId] ?? muscleId;
}
