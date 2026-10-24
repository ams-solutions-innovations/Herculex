import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:intl/intl.dart' show DateFormat;

part 'weight_picker_sheet/_painter.part.dart';

/// Modal bottom sheet with an animated semicircular scale dial ("pol kroga tehtnice")
/// for logging bodyweight, styled to match Herculex's frosted glass design UI.
class WeightPickerSheet extends ConsumerStatefulWidget {
  final double? initialKg;
  final double? previousKg;
  final String? title;

  const WeightPickerSheet({
    super.key,
    this.initialKg,
    this.previousKg,
    this.title,
  });

  /// Shows the weight picker sheet and returns the selected weight in kilograms,
  /// or null if dismissed.
  static Future<double?> show(
    BuildContext context, {
    double? initialKg,
    double? previousKg,
    String? title,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WeightPickerSheet(
        initialKg: initialKg,
        previousKg: previousKg,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<WeightPickerSheet> createState() => _WeightPickerSheetState();
}

class _WeightPickerSheetState extends ConsumerState<WeightPickerSheet>
    with TickerProviderStateMixin {
  late bool _isMetric;
  late double _currentDisplayWeight;
  double? _previousDisplayWeight;

  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;

  late AnimationController _stepController;
  late Animation<double> _stepAnimation;

  int _lastHapticTenth = 0;
  bool _isDragging = false;
  bool _isManualEditing = false;
  late TextEditingController _manualInputCtrl;
  final FocusNode _manualInputFocus = FocusNode();

  double get _minWeight => _isMetric ? 20.0 : 45.0;
  double get _maxWeight => _isMetric ? 300.0 : 660.0;
  String get _unitSuffix => _isMetric ? 'kg' : 'lb';

  @override
  void initState() {
    super.initState();
    final fmt = ref.read(weightFormatProvider);
    _isMetric = fmt.isMetric;

    final targetKg = widget.initialKg ?? 75.0;
    _currentDisplayWeight = _toDisplay(targetKg).clamp(_minWeight, _maxWeight);
    if (widget.previousKg != null) {
      _previousDisplayWeight = _toDisplay(widget.previousKg!);
    }

    _lastHapticTenth = (_currentDisplayWeight * 10).round();
    _manualInputCtrl = TextEditingController(
      text: _currentDisplayWeight.toStringAsFixed(1),
    );

    // Entrance animation: dial spins smoothly up into position like an analog scale
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    final startWeight = (_currentDisplayWeight - (_isMetric ? 7.0 : 15.0))
        .clamp(_minWeight, _maxWeight);

    _entranceAnimation =
        Tween<double>(begin: startWeight, end: _currentDisplayWeight).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        )..addListener(() {
          if (_entranceController.isAnimating) {
            _updateWeightFromAnimation(_entranceAnimation.value);
          }
        });

    _stepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _stepController.dispose();
    _manualInputCtrl.dispose();
    _manualInputFocus.dispose();
    super.dispose();
  }

  double _toDisplay(double kg) => _isMetric ? kg : Units.kgToLb(kg);
  double _toKg(double display) => _isMetric ? display : Units.lbToKg(display);

  void _updateWeightFromAnimation(double value) {
    final clamped = value.clamp(_minWeight, _maxWeight);
    final tenth = (clamped * 10).round();
    if (tenth != _lastHapticTenth) {
      _lastHapticTenth = tenth;
      Haptics.selection();
    }
    setState(() => _currentDisplayWeight = clamped);
  }

  void _onDragStart(DragStartDetails details) {
    _entranceController.stop();
    _stepController.stop();
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final deltaWeight = -details.delta.dx / 22.0;
    final newWeight = (_currentDisplayWeight + deltaWeight).clamp(
      _minWeight,
      _maxWeight,
    );
    final tenth = (newWeight * 10).round();
    if (tenth != _lastHapticTenth) {
      _lastHapticTenth = tenth;
      Haptics.selection();
    }
    setState(() => _currentDisplayWeight = newWeight);
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 300) {
      final flingDelta = (-velocity / 600.0).clamp(-8.0, 8.0);
      _animateToWeight(_currentDisplayWeight + flingDelta, durationMs: 400);
    } else {
      final snapped = ((_currentDisplayWeight * 10).round()) / 10.0;
      _animateToWeight(snapped, durationMs: 150);
    }
  }

  void _animateToWeight(double target, {int durationMs = 220}) {
    _entranceController.stop();
    _stepController.stop();

    final clamped = target.clamp(_minWeight, _maxWeight);
    final rounded = ((clamped * 10).round()) / 10.0;

    _stepController.duration = Duration(milliseconds: durationMs);
    _stepAnimation =
        Tween<double>(begin: _currentDisplayWeight, end: rounded).animate(
          CurvedAnimation(parent: _stepController, curve: Curves.easeOutCubic),
        )..addListener(() {
          if (_stepController.isAnimating) {
            _updateWeightFromAnimation(_stepAnimation.value);
          }
        });

    _stepController.forward(from: 0);
  }

  void _adjustBy(double delta) {
    Haptics.light();
    _animateToWeight(_currentDisplayWeight + delta);
  }

  void _toggleUnit() {
    Haptics.selection();
    _entranceController.stop();
    _stepController.stop();

    setState(() {
      if (_isMetric) {
        _isMetric = false;
        _currentDisplayWeight = Units.kgToLb(
          _currentDisplayWeight,
        ).clamp(_minWeight, _maxWeight);
        if (_previousDisplayWeight != null) {
          _previousDisplayWeight = Units.kgToLb(_previousDisplayWeight!);
        }
      } else {
        _isMetric = true;
        _currentDisplayWeight = Units.lbToKg(
          _currentDisplayWeight,
        ).clamp(_minWeight, _maxWeight);
        if (_previousDisplayWeight != null) {
          _previousDisplayWeight = Units.lbToKg(_previousDisplayWeight!);
        }
      }
      _lastHapticTenth = (_currentDisplayWeight * 10).round();
      _manualInputCtrl.text = _currentDisplayWeight.toStringAsFixed(1);
    });
  }

  void _commitManualInput() {
    final parsed = double.tryParse(_manualInputCtrl.text);
    if (parsed != null && parsed >= _minWeight && parsed <= _maxWeight) {
      _animateToWeight(parsed);
    }
    setState(() => _isManualEditing = false);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final bottomPadding = MediaQuery.of(context).padding.bottom + HxSpace.x3;
    final currentRounded = ((_currentDisplayWeight * 10).round()) / 10.0;

    return ClipRRect(
      borderRadius: HxRadius.sheetTop,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: hx.surfaceContainer.withValues(
              alpha: hx.isDark ? 0.88 : 0.94,
            ),
            borderRadius: HxRadius.sheetTop,
            border: Border(
              top: BorderSide(
                color: hx.glassBorder.withValues(alpha: hx.isDark ? 0.6 : 0.9),
                width: 1.2,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 6),
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: hx.outlineVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
                    child: Row(
                      children: [
                        HxGlass(
                          shape: BoxShape.circle,
                          padding: const EdgeInsets.all(8),
                          fill: hx.primary.withValues(alpha: 0.12),
                          borderColor: hx.primary.withValues(alpha: 0.25),
                          child: Icon(
                            Icons.monitor_weight_outlined,
                            size: 18,
                            color: hx.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title ?? 'Log weight',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                DateFormat(
                                  'EEEE, MMM d',
                                ).format(DateTime.now()),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: hx.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: _toggleUnit,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: hx.surfaceVariant.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: hx.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _unitSuffix.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: hx.primary,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 14,
                                  color: hx.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: hx.onSurfaceVariant,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final dialWidth = math.min(constraints.maxWidth, 360.0);
                      const dialHeight = 205.0;

                      return GestureDetector(
                        onHorizontalDragStart: _onDragStart,
                        onHorizontalDragUpdate: _onDragUpdate,
                        onHorizontalDragEnd: _onDragEnd,
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: dialWidth,
                          height: dialHeight,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: Size(dialWidth, dialHeight),
                                painter: _ScaleSemicirclePainter(
                                  currentWeight: _currentDisplayWeight,
                                  isMetric: _isMetric,
                                  primaryColor: hx.primary,
                                  onSurface: hx.onSurface,
                                  outline: hx.outline,
                                  glassBorder: hx.glassBorder,
                                  isDragging: _isDragging,
                                ),
                              ),
                              Positioned(
                                top: 84,
                                child: _isManualEditing
                                    ? _ManualWeightInput(
                                        controller: _manualInputCtrl,
                                        focusNode: _manualInputFocus,
                                        unitSuffix: _unitSuffix,
                                        onSubmitted: _commitManualInput,
                                      )
                                    : _DigitalReadoutBadge(
                                        currentRounded: currentRounded,
                                        unitSuffix: _unitSuffix,
                                        previousDisplayWeight:
                                            _previousDisplayWeight,
                                        onTap: () {
                                          setState(() {
                                            _isManualEditing = true;
                                            _manualInputCtrl.text =
                                                currentRounded.toStringAsFixed(
                                                  1,
                                                );
                                          });
                                          _manualInputFocus.requestFocus();
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _FrostedStepButton(
                          label: '-1.0',
                          onTap: () => _adjustBy(-1.0),
                        ),
                        const SizedBox(width: 10),
                        _FrostedStepButton(
                          label: '-0.1',
                          onTap: () => _adjustBy(-0.1),
                        ),
                        const SizedBox(width: 14),
                        _FrostedStepButton(
                          label: '+0.1',
                          onTap: () => _adjustBy(0.1),
                        ),
                        const SizedBox(width: 10),
                        _FrostedStepButton(
                          label: '+1.0',
                          onTap: () => _adjustBy(1.0),
                        ),
                      ],
                    ),
                  ),
                  if (widget.previousKg != null) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        Haptics.selection();
                        _animateToWeight(_toDisplay(widget.previousKg!));
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Text(
                          'Reset to last: ${_toDisplay(widget.previousKg!).toStringAsFixed(1)} $_unitSuffix',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hx.secondary,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: hx.onSurface,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              side: BorderSide(
                                color: hx.outlineVariant.withValues(alpha: 0.6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              Haptics.medium();
                              final resultKg = _toKg(currentRounded);
                              Navigator.of(context).pop(resultKg);
                            },
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              'Save ${currentRounded.toStringAsFixed(1)} $_unitSuffix',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: hx.primary,
                              foregroundColor: hx.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
