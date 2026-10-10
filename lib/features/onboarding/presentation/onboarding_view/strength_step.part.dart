part of '../onboarding_view.dart';

/// Optional last onboarding step: what the user can already lift. It only
/// seeds the Herculex rank band; skipping it leaves them at Novice until
/// their logged lifts say otherwise.
class _StrengthStep extends StatefulWidget {
  const _StrengthStep({
    required this.bodyweightKg,
    required this.sex,
    required this.onChanged,
  });

  final double? bodyweightKg;
  final BiologicalSex? sex;
  final ValueChanged<StrengthSurvey?> onChanged;

  @override
  State<_StrengthStep> createState() => _StrengthStepState();
}

class _StrengthStepState extends State<_StrengthStep> {
  TrainingStyle _style = TrainingStyle.both;
  final _weightCtrls = <StrengthLift, TextEditingController>{
    for (final lift in StrengthLift.values)
      if (lift.group == StrengthGroup.barbell) lift: TextEditingController(),
  };
  final _repsCtrls = <StrengthLift, TextEditingController>{
    for (final lift in StrengthLift.values) lift: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in [..._weightCtrls.values, ..._repsCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  StrengthSurvey get _survey {
    final lifts = <StrengthLift, SurveyLiftEntry>{};
    for (final lift in StrengthLift.values) {
      if (!_style.includes(lift.group)) continue;
      final reps = int.tryParse(_repsCtrls[lift]!.text.trim()) ?? 0;
      final weight = double.tryParse(_weightCtrls[lift]?.text.trim() ?? '');
      final hasWeight = lift.group != StrengthGroup.barbell || weight != null;
      if (reps > 0 && hasWeight) {
        lifts[lift] = SurveyLiftEntry(weightKg: weight, reps: reps);
      }
    }
    return StrengthSurvey(style: _style, lifts: lifts);
  }

  void _changed() {
    setState(() {});
    widget.onChanged(_survey);
  }

  LevelBand get _startingBand {
    final bests = const LiftBestExtractor().extract(
      samples: const [],
      profileBodyweightKg: widget.bodyweightKg,
      survey: _survey,
    );
    return const StrengthTierEvaluator()
        .evaluate(bests: bests, sex: widget.sex)
        .tier;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final band = _startingBand;
    final showBarbell = _style.includes(StrengthGroup.barbell);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What can you lift?', style: theme.textTheme.displayMedium),
          const SizedBox(height: HxSpace.x2),
          Text(
            'Optional. It sets your starting rank. Skip it and Herculex '
            'places you from the lifts you log.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hx.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HxSpace.x6),
          HxTopTabs(
            labels: [for (final s in TrainingStyle.values) s.label],
            index: _style.index,
            onChanged: (i) {
              _style = TrainingStyle.values[i];
              _changed();
            },
          ),
          const SizedBox(height: HxSpace.x5),
          if (showBarbell) ...[
            _groupHeader(theme, 'Best set · weight (kg) × reps'),
            for (final lift in StrengthLift.values)
              if (lift.group == StrengthGroup.barbell) _barbellRow(theme, lift),
            if (widget.bodyweightKg == null)
              Padding(
                padding: const EdgeInsets.only(top: HxSpace.x1),
                child: Text(
                  'Add your weight on the previous step so barbell lifts '
                  'count.',
                  style: theme.textTheme.bodySmall?.copyWith(color: hx.warning),
                ),
              ),
            const SizedBox(height: HxSpace.x5),
          ],
          if (_style.includes(StrengthGroup.calisthenics)) ...[
            _groupHeader(theme, 'Most strict reps in one set'),
            for (final lift in StrengthLift.values)
              if (lift.group == StrengthGroup.calisthenics)
                _repsRow(theme, lift),
            const SizedBox(height: HxSpace.x5),
          ],
          HxCard(
            accent: band.color(context),
            padding: const EdgeInsets.all(HxSpace.x4),
            child: Row(
              children: [
                Icon(band.icon, color: band.color(context)),
                const SizedBox(width: HxSpace.x3),
                Expanded(
                  child: Text(
                    "You'll start at ${band.label}",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HxSpace.x4),
        ],
      ),
    );
  }

  Widget _groupHeader(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: HxSpace.x2),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _barbellRow(ThemeData theme, StrengthLift lift) => Padding(
    padding: const EdgeInsets.only(bottom: HxSpace.x2),
    child: Row(
      children: [
        Expanded(child: Text(lift.label, style: theme.textTheme.bodyLarge)),
        SizedBox(width: 84, child: _input(_weightCtrls[lift]!, 'kg')),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text('×'),
        ),
        SizedBox(width: 64, child: _input(_repsCtrls[lift]!, 'reps')),
      ],
    ),
  );

  Widget _repsRow(ThemeData theme, StrengthLift lift) => Padding(
    padding: const EdgeInsets.only(bottom: HxSpace.x2),
    child: Row(
      children: [
        Expanded(child: Text(lift.label, style: theme.textTheme.bodyLarge)),
        SizedBox(width: 64, child: _input(_repsCtrls[lift]!, 'reps')),
      ],
    ),
  );

  Widget _input(TextEditingController controller, String hint) {
    final hx = context.hx;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      maxLength: 5,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: hx.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HxRadius.sm),
          borderSide: BorderSide(color: hx.outlineVariant),
        ),
      ),
    );
  }
}
