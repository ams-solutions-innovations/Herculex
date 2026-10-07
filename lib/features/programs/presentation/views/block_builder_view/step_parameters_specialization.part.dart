part of '../block_builder_view.dart';

mixin _StepParametersSpecializationMixin on _BuilderStateBase {
  static const _specializationCompatibleSplits = <SplitType>{
    SplitType.fullBody,
    SplitType.fullBodyLinear,
    SplitType.fullBodyAb,
    SplitType.upperLower,
    SplitType.upperLowerFullBody,
    SplitType.ppl,
  };

  @override
  Future<bool> _showSpecializationModal(ThemeData theme) async {
    var tempLift = _specializationLift;
    final currentCtrl = TextEditingController(text: _currentSquatCtrl.text);
    final targetCtrl = TextEditingController(
      text: _targetSquatCtrl.text.isEmpty
          ? _defaultTargetFor(_specializationLift).toString()
          : _targetSquatCtrl.text,
    );
    var tempStickingPoint = _liftStickingPoint;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final stickingPoints = PrimaryLiftStickingPoint.values
                .where((point) => point.supportedLifts.contains(tempLift))
                .toList(growable: false);
            if (!stickingPoints.contains(tempStickingPoint)) {
              tempStickingPoint = PrimaryLiftStickingPoint.unknown;
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primary lift specialization',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select which lift to prioritize and set your current baseline and target.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<PrimaryLift>(
                        initialValue: tempLift,
                        dropdownColor: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.secondary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Target lift',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: [
                          for (final lift in PrimaryLift.values)
                            DropdownMenuItem(
                              value: lift,
                              child: Text(lift.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() {
                            final oldDefault = _defaultTargetFor(
                              tempLift,
                            ).toString();
                            if (targetCtrl.text.trim() == oldDefault) {
                              targetCtrl.text = _defaultTargetFor(
                                value,
                              ).toString();
                            }
                            tempLift = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PremiumTextField(
                              controller: currentCtrl,
                              hintText: tempLift == PrimaryLift.pullUp
                                  ? 'Current added kg'
                                  : 'Current load (kg)',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PremiumTextField(
                              controller: targetCtrl,
                              hintText: tempLift == PrimaryLift.pullUp
                                  ? 'Target added kg'
                                  : 'Target load (kg)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PrimaryLiftStickingPoint>(
                        initialValue: tempStickingPoint,
                        dropdownColor: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.secondary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Where does the lift slow down?',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: [
                          for (final point in stickingPoints)
                            DropdownMenuItem(
                              value: point,
                              child: Text(point.label),
                            ),
                        ],
                        onChanged: (value) => setSheetState(
                          () => tempStickingPoint =
                              value ?? PrimaryLiftStickingPoint.unknown,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        PrimaryLiftSpecialization(
                          lift: tempLift,
                          currentKg: 0,
                          targetKg: 0,
                          weeks: _weeks,
                          stickingPoint: tempStickingPoint,
                        ).assistanceFocus,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                        ),
                      ),
                      if (tempLift == PrimaryLift.pullUp) ...[
                        const SizedBox(height: 10),
                        Text(
                          'For pull-ups, use 0 for bodyweight and enter added external load in kg when applicable.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final current = double.tryParse(
                                  currentCtrl.text.trim().replaceAll(',', '.'),
                                );
                                if (current == null || current < 0) {
                                  AppNotice.show(
                                    context,
                                    'Please enter your current load (kg).',
                                    kind: AppNoticeKind.info,
                                  );
                                  return;
                                }
                                Navigator.pop(context, true);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _specializationLift = tempLift;
        _currentSquatCtrl.text = currentCtrl.text.trim();
        _targetSquatCtrl.text = targetCtrl.text.trim();
        _liftStickingPoint = tempStickingPoint;
        _useLiftSpecialization = true;
        if (!_specializationCompatibleSplits.contains(_split)) {
          _split = SplitType.fullBody;
          _daysPerWeek = 3;
          _model = PeriodizationModel.linear;
        }
        _weeks = _liftRecommendedWeeks;
        _clearCustomWeeklyPlacement();
      });
      return true;
    }
    return false;
  }

  @override
  double? get _currentSquatKg =>
      double.tryParse(_currentSquatCtrl.text.trim().replaceAll(',', '.'));

  @override
  double get _targetSquatKg =>
      double.tryParse(_targetSquatCtrl.text.trim().replaceAll(',', '.')) ?? 140;

  @override
  int get _liftRecommendedWeeks => PrimaryLiftSpecialization.recommendedWeeks(
    currentKg: _currentSquatKg ?? 0,
    targetKg: _targetSquatKg,
    isNovice: _experience == ExperienceLevel.novice,
  );

  @override
  PrimaryLiftSpecialization? get _primaryLiftSpecialization {
    if (!_useLiftSpecialization || _currentSquatKg == null) return null;
    return PrimaryLiftSpecialization(
      lift: _specializationLift,
      currentKg: _currentSquatKg!,
      targetKg: _targetSquatKg,
      weeks: _weeks,
      stickingPoint: _liftStickingPoint,
    );
  }

  int _defaultTargetFor(PrimaryLift lift) => switch (lift) {
    PrimaryLift.squat => 140,
    PrimaryLift.deadlift => 180,
    PrimaryLift.benchPress => 100,
    PrimaryLift.overheadPress => 60,
    PrimaryLift.pullUp => 20,
  };
}
