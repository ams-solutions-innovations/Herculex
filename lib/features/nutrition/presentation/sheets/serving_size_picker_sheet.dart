import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Modal bottom sheet allowing food serving size selection via either our
/// signature semicircular scale dial ("pol krog tehtnice") or direct numeric keypad.
class ServingSizePickerSheet extends StatefulWidget {
  final TextEditingController quantityController;
  final bool isFood;
  final String selectedUnit;
  final List<String> availableUnits;
  final ValueChanged<String> onUnitSelected;
  final String? foodTitle;
  final ValueChanged<double>? onChanged;
  final bool initialKeypadMode;

  const ServingSizePickerSheet({
    super.key,
    required this.quantityController,
    required this.isFood,
    required this.selectedUnit,
    required this.availableUnits,
    required this.onUnitSelected,
    this.foodTitle,
    this.onChanged,
    this.initialKeypadMode = false,
  });

  /// Shows the serving size & unit picker bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required TextEditingController quantityController,
    required bool isFood,
    required String selectedUnit,
    required List<String> availableUnits,
    required ValueChanged<String> onUnitSelected,
    String? foodTitle,
    ValueChanged<double>? onChanged,
    bool initialKeypadMode = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServingSizePickerSheet(
        quantityController: quantityController,
        isFood: isFood,
        selectedUnit: selectedUnit,
        availableUnits: availableUnits,
        onUnitSelected: onUnitSelected,
        foodTitle: foodTitle,
        onChanged: onChanged,
        initialKeypadMode: initialKeypadMode,
      ),
    );
  }

  @override
  State<ServingSizePickerSheet> createState() => _ServingSizePickerSheetState();
}

class _ServingSizePickerSheetState extends State<ServingSizePickerSheet>
    with TickerProviderStateMixin {
  late String _currentUnit;
  late double _currentAmount;
  late bool _isKeypadMode;

  final FocusNode _keypadFocusNode = FocusNode();

  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;

  late AnimationController _stepController;
  late Animation<double> _stepAnimation;

  int _lastHapticUnit = 0;
  bool _isDragging = false;

  bool get _isIntegerUnit => _currentUnit == 'g' || _currentUnit == 'ml';
  double get _minAmount => _isIntegerUnit ? 1.0 : 0.1;
  double get _maxAmount => _isIntegerUnit ? 5000.0 : 200.0;
  String get _unitSuffix => widget.isFood ? _currentUnit : 'servings';

  @override
  void initState() {
    super.initState();
    _currentUnit = widget.selectedUnit;
    _isKeypadMode = widget.initialKeypadMode;

    final parsed = double.tryParse(
      widget.quantityController.text.trim().replaceAll(',', '.'),
    );
    _currentAmount = (parsed ?? (_isIntegerUnit ? 100.0 : 1.0)).clamp(
      _minAmount,
      _maxAmount,
    );

    _lastHapticUnit = _isIntegerUnit
        ? _currentAmount.round()
        : (_currentAmount * 10).round();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    final startAmount = (_currentAmount - (_isIntegerUnit ? 20.0 : 2.0)).clamp(
      _minAmount,
      _maxAmount,
    );

    _entranceAnimation =
        Tween<double>(begin: startAmount, end: _currentAmount).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        )..addListener(() {
          if (_entranceController.isAnimating) {
            _updateAmountFromAnimation(_entranceAnimation.value);
          }
        });

    _stepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    if (!_isKeypadMode) {
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _stepController.dispose();
    _keypadFocusNode.dispose();
    super.dispose();
  }

  void _syncQuantityToController(double value) {
    final String text;
    if (_isIntegerUnit) {
      text = value.round().toString();
    } else {
      final roundedTenth = ((value * 10).round()) / 10.0;
      text = roundedTenth % 1 == 0
          ? roundedTenth.toStringAsFixed(0)
          : roundedTenth.toStringAsFixed(1);
    }
    if (widget.quantityController.text != text) {
      widget.quantityController.text = text;
      widget.onChanged?.call(value);
    }
  }

  void _updateAmountFromAnimation(double value) {
    final clamped = value.clamp(_minAmount, _maxAmount);
    final effectiveValue = _isIntegerUnit
        ? clamped.roundToDouble()
        : (((clamped * 10).round()) / 10.0);
    final hapticUnit = _isIntegerUnit
        ? effectiveValue.round()
        : (effectiveValue * 10).round();
    if (hapticUnit != _lastHapticUnit) {
      _lastHapticUnit = hapticUnit;
      Haptics.selection();
    }
    setState(() => _currentAmount = effectiveValue);
    _syncQuantityToController(effectiveValue);
  }

  void _onDragStart(DragStartDetails details) {
    _entranceController.stop();
    _stepController.stop();
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final deltaAmount = _isIntegerUnit
        ? -details.delta.dx / 2.2
        : -details.delta.dx / 22.0;

    final newAmount = (_currentAmount + deltaAmount).clamp(
      _minAmount,
      _maxAmount,
    );

    final hapticUnit = _isIntegerUnit
        ? newAmount.round()
        : (newAmount * 10).round();
    if (hapticUnit != _lastHapticUnit) {
      _lastHapticUnit = hapticUnit;
      Haptics.selection();
    }

    setState(() => _currentAmount = newAmount);
    _syncQuantityToController(newAmount);
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 300) {
      final flingDelta = _isIntegerUnit
          ? (-velocity / 60.0).clamp(-80.0, 80.0)
          : (-velocity / 600.0).clamp(-8.0, 8.0);
      _animateToAmount(_currentAmount + flingDelta, durationMs: 400);
    } else {
      final snapped = _isIntegerUnit
          ? _currentAmount.roundToDouble()
          : ((_currentAmount * 10).round()) / 10.0;
      _animateToAmount(snapped, durationMs: 150);
    }
  }

  void _animateToAmount(double target, {int durationMs = 220}) {
    _entranceController.stop();
    _stepController.stop();

    final clamped = target.clamp(_minAmount, _maxAmount);
    final rounded = _isIntegerUnit
        ? clamped.roundToDouble()
        : ((clamped * 10).round()) / 10.0;

    _stepController.duration = Duration(milliseconds: durationMs);
    _stepAnimation =
        Tween<double>(begin: _currentAmount, end: rounded).animate(
          CurvedAnimation(parent: _stepController, curve: Curves.easeOutCubic),
        )..addListener(() {
          if (_stepController.isAnimating) {
            _updateAmountFromAnimation(_stepAnimation.value);
          }
        });

    _stepController.forward(from: 0);
  }

  void _adjustBy(double delta) {
    Haptics.light();
    _animateToAmount(_currentAmount + delta);
  }

  void _setMode({required bool isKeypad}) {
    if (_isKeypadMode == isKeypad) return;
    Haptics.selection();
    _entranceController.stop();
    _stepController.stop();

    if (isKeypad) {
      _syncQuantityToController(_currentAmount);
      setState(() => _isKeypadMode = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _keypadFocusNode.requestFocus();
        }
      });
    } else {
      _keypadFocusNode.unfocus();
      final parsed = double.tryParse(
        widget.quantityController.text.trim().replaceAll(',', '.'),
      );
      if (parsed != null && parsed >= _minAmount && parsed <= _maxAmount) {
        _currentAmount = parsed;
      }
      setState(() => _isKeypadMode = false);
      _animateToAmount(_currentAmount, durationMs: 250);
    }
  }

  void _selectUnit(String nextUnit) {
    if (nextUnit == _currentUnit) return;
    Haptics.selection();
    _entranceController.stop();
    _stepController.stop();

    _currentUnit = nextUnit;
    widget.onUnitSelected(nextUnit);

    final converted = double.tryParse(
      widget.quantityController.text.trim().replaceAll(',', '.'),
    );
    if (converted != null) {
      _currentAmount = converted.clamp(_minAmount, _maxAmount);
      _lastHapticUnit = _isIntegerUnit
          ? _currentAmount.round()
          : (_currentAmount * 10).round();
      if (!_isKeypadMode) {
        _animateToAmount(_currentAmount, durationMs: 250);
      }
    }
    setState(() {});
  }

  String get _formattedAmount {
    if (_isIntegerUnit) {
      return _currentAmount.round().toString();
    }
    final roundedTenth = ((_currentAmount * 10).round()) / 10.0;
    return roundedTenth % 1 == 0
        ? roundedTenth.toStringAsFixed(0)
        : roundedTenth.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom + HxSpace.x3;

    return ClipRRect(
      borderRadius: HxRadius.sheetTop,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: hx.surfaceContainer.withValues(
              alpha: hx.isDark ? 0.90 : 0.96,
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
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: bottomInset > 0 ? bottomInset + 16 : bottomPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 6),
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: hx.outlineVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with Title and Mode Toggle
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 16, 10),
                    child: Row(
                      children: [
                        HxGlass(
                          shape: BoxShape.circle,
                          padding: const EdgeInsets.all(8),
                          fill: hx.primary.withValues(alpha: 0.12),
                          borderColor: hx.primary.withValues(alpha: 0.25),
                          child: Icon(
                            Icons.scale_rounded,
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
                                'Serving Size & Unit',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (widget.foodTitle != null)
                                Text(
                                  widget.foodTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hx.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Mode Toggle Pill: Dial vs Keypad
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: hx.surfaceVariant.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hx.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ModeButton(
                                icon: Icons.speed_rounded,
                                label: 'Dial',
                                isSelected: !_isKeypadMode,
                                onTap: () => _setMode(isKeypad: false),
                              ),
                              _ModeButton(
                                icon: Icons.dialpad_rounded,
                                label: 'Keypad',
                                isSelected: _isKeypadMode,
                                onTap: () => _setMode(isKeypad: true),
                              ),
                            ],
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

                  // Mode content: Dial or Keypad
                  if (!_isKeypadMode) ...[
                    // Semicircular scale dial
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
                                  painter: _ServingSizeDialPainter(
                                    currentAmount: _currentAmount,
                                    isIntegerUnit: _isIntegerUnit,
                                    primaryColor: hx.primary,
                                    onSurface: hx.onSurface,
                                    outline: hx.outline,
                                    glassBorder: hx.glassBorder,
                                    isDragging: _isDragging,
                                  ),
                                ),
                                Positioned(
                                  top: 84,
                                  child: _DialReadoutBadge(
                                    formattedAmount: _formattedAmount,
                                    unitSuffix: _unitSuffix,
                                    onTap: () => _setMode(isKeypad: true),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Quick Step Adjustment Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _isIntegerUnit
                            ? [
                                _FrostedStepButton(
                                  label: '-10',
                                  onTap: () => _adjustBy(-10),
                                ),
                                const SizedBox(width: 10),
                                _FrostedStepButton(
                                  label: '-1',
                                  onTap: () => _adjustBy(-1),
                                ),
                                const SizedBox(width: 14),
                                _FrostedStepButton(
                                  label: '+1',
                                  onTap: () => _adjustBy(1),
                                ),
                                const SizedBox(width: 10),
                                _FrostedStepButton(
                                  label: '+10',
                                  onTap: () => _adjustBy(10),
                                ),
                              ]
                            : [
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
                  ] else ...[
                    // Keypad mode: direct TextField
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: TextField(
                        controller: widget.quantityController,
                        focusNode: _keypadFocusNode,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hx.onSurface,
                        ),
                        decoration: InputDecoration(
                          suffixText: _unitSuffix,
                          suffixStyle: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          filled: true,
                          fillColor: hx.surfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: hx.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: hx.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: hx.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(
                            val.trim().replaceAll(',', '.'),
                          );
                          if (parsed != null &&
                              parsed >= _minAmount &&
                              parsed <= _maxAmount) {
                            _currentAmount = parsed;
                            widget.onChanged?.call(parsed);
                          }
                        },
                      ),
                    ),
                  ],

                  // Unit Selector Section (when logging food)
                  if (widget.isFood && widget.availableUnits.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Unit',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final u in widget.availableUnits)
                            GestureDetector(
                              onTap: () => _selectUnit(u),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _currentUnit == u
                                      ? hx.primary
                                      : hx.surfaceVariant,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _currentUnit == u
                                        ? hx.primary
                                        : hx.outlineVariant.withValues(
                                            alpha: 0.4,
                                          ),
                                  ),
                                ),
                                child: Text(
                                  u,
                                  style: TextStyle(
                                    color: _currentUnit == u
                                        ? hx.onPrimary
                                        : hx.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Done Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Haptics.selection();
                          final text = widget.quantityController.text
                              .trim()
                              .replaceAll(',', '.');
                          final parsed = double.tryParse(text);
                          if (parsed != null &&
                              parsed >= _minAmount &&
                              parsed <= _maxAmount) {
                            widget.onChanged?.call(parsed);
                          }
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hx.primary,
                          foregroundColor: hx.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
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

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? hx.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? hx.onPrimary : hx.secondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? hx.onPrimary : hx.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialReadoutBadge extends StatelessWidget {
  final String formattedAmount;
  final String unitSuffix;
  final VoidCallback onTap;

  const _DialReadoutBadge({
    required this.formattedAmount,
    required this.unitSuffix,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formattedAmount,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                    color: hx.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unitSuffix,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: hx.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: hx.secondary.withValues(alpha: 0.6),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Drag scale to adjust · Tap to type',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: hx.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrostedStepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FrostedStepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: HxGlass(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          borderRadius: BorderRadius.circular(16),
          fill: HxGlass.frostedFill(hx),
          borderColor: HxGlass.frostedBorder(hx),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: hx.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServingSizeDialPainter extends CustomPainter {
  final double currentAmount;
  final bool isIntegerUnit;
  final Color primaryColor;
  final Color onSurface;
  final Color outline;
  final Color glassBorder;
  final bool isDragging;

  _ServingSizeDialPainter({
    required this.currentAmount,
    required this.isIntegerUnit,
    required this.primaryColor,
    required this.onSurface,
    required this.outline,
    required this.glassBorder,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height + 25);
    final radius = size.width * 0.54;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final rimPaint = Paint()
      ..color = glassBorder.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const startAngle = -math.pi * 0.92;
    const sweepAngle = math.pi * 0.84;
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, rimPaint);

    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDragging ? 0.22 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(arcRect, -math.pi / 2 - 0.35, 0.70, false, glowPaint);

    if (isIntegerUnit) {
      // Grams / Milliliters: 1 unit = 1g/ml.
      // Major tick every 10g, medium at 5g, minor at 1g.
      const anglePerUnit = 0.028;
      final minVal = math.max(0.0, currentAmount - 45.0);
      final maxVal = currentAmount + 45.0;

      final minInt = minVal.floor();
      final maxInt = maxVal.ceil();

      for (int v = minInt; v <= maxInt; v++) {
        final angle = -math.pi / 2 + (v - currentAmount) * anglePerUnit;
        final angleDistFromCenter = (angle - (-math.pi / 2)).abs();
        if (angleDistFromCenter > 1.25) continue;

        final fade = (1.0 - (angleDistFromCenter - 0.75) / 0.45).clamp(
          0.0,
          1.0,
        );
        if (fade <= 0.01) continue;

        final isMajor = v % 10 == 0;
        final isMedium = v % 5 == 0 && !isMajor;

        final tickLength = isMajor ? 16.0 : (isMedium ? 10.0 : 5.5);
        final tickWidth = isMajor ? 2.4 : (isMedium ? 1.6 : 1.0);

        final tickColor = isMajor
            ? onSurface.withValues(alpha: 0.85 * fade)
            : (isMedium
                  ? onSurface.withValues(alpha: 0.50 * fade)
                  : outline.withValues(alpha: 0.30 * fade));

        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        final pOuter = Offset(
          center.dx + radius * cosA,
          center.dy + radius * sinA,
        );
        final pInner = Offset(
          center.dx + (radius - tickLength) * cosA,
          center.dy + (radius - tickLength) * sinA,
        );

        final tickPaint = Paint()
          ..color = tickColor
          ..strokeWidth = tickWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(pOuter, pInner, tickPaint);

        if (isMajor && fade > 0.2) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '$v',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.80 * fade),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final labelRadius = radius - 28.0;
          final pLabel = Offset(
            center.dx + labelRadius * cosA,
            center.dy + labelRadius * sinA,
          );

          textPainter.paint(
            canvas,
            Offset(
              pLabel.dx - textPainter.width / 2,
              pLabel.dy - textPainter.height / 2,
            ),
          );
        }
      }
    } else {
      // Decimal units (servings, oz, scoop, etc.):
      // Major tick every 1.0, medium at 0.5, minor at 0.1.
      const anglePerUnit = 0.28;
      final minVal = math.max(0.0, (currentAmount - 4.5)).floorToDouble();
      final maxVal = (currentAmount + 4.5).ceilToDouble();

      final minTenth = (minVal * 10).round();
      final maxTenth = (maxVal * 10).round();

      for (int t = minTenth; t <= maxTenth; t++) {
        final v = t / 10.0;
        final angle = -math.pi / 2 + (v - currentAmount) * anglePerUnit;
        final angleDistFromCenter = (angle - (-math.pi / 2)).abs();
        if (angleDistFromCenter > 1.25) continue;

        final fade = (1.0 - (angleDistFromCenter - 0.75) / 0.45).clamp(
          0.0,
          1.0,
        );
        if (fade <= 0.01) continue;

        final isMajor = t % 10 == 0;
        final isMedium = t % 5 == 0 && !isMajor;

        final tickLength = isMajor ? 16.0 : (isMedium ? 10.0 : 5.5);
        final tickWidth = isMajor ? 2.4 : (isMedium ? 1.6 : 1.0);

        final tickColor = isMajor
            ? onSurface.withValues(alpha: 0.85 * fade)
            : (isMedium
                  ? onSurface.withValues(alpha: 0.50 * fade)
                  : outline.withValues(alpha: 0.30 * fade));

        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        final pOuter = Offset(
          center.dx + radius * cosA,
          center.dy + radius * sinA,
        );
        final pInner = Offset(
          center.dx + (radius - tickLength) * cosA,
          center.dy + (radius - tickLength) * sinA,
        );

        final tickPaint = Paint()
          ..color = tickColor
          ..strokeWidth = tickWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(pOuter, pInner, tickPaint);

        if (isMajor && fade > 0.2) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '${v.round()}',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.80 * fade),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final labelRadius = radius - 28.0;
          final pLabel = Offset(
            center.dx + labelRadius * cosA,
            center.dy + labelRadius * sinA,
          );

          textPainter.paint(
            canvas,
            Offset(
              pLabel.dx - textPainter.width / 2,
              pLabel.dy - textPainter.height / 2,
            ),
          );
        }
      }
    }

    final needleTopY = center.dy - radius - 10;
    final needleBottomY = center.dy - radius + 15;

    final needleGlowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(
      Offset(center.dx, needleTopY),
      Offset(center.dx, needleBottomY),
      needleGlowPaint,
    );

    final needlePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx, needleTopY),
      Offset(center.dx, needleBottomY),
      needlePaint,
    );

    final pipCenter = Offset(center.dx, needleTopY + 2);
    final pipGlowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pipCenter, 6.0, pipGlowPaint);

    final pipInnerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pipCenter, 2.8, pipInnerPaint);
  }

  @override
  bool shouldRepaint(covariant _ServingSizeDialPainter oldDelegate) {
    return oldDelegate.currentAmount != currentAmount ||
        oldDelegate.isIntegerUnit != isIntegerUnit ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.primaryColor != primaryColor;
  }
}
