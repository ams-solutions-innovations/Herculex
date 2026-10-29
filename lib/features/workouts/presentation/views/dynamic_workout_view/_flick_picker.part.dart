part of '../dynamic_workout_view.dart';

/// Discrete Flick Number Picker for Weight, Reps & Duration.
/// Allows flicking/swiping up or down rep-by-rep, scrolling a mouse wheel,
/// and tapping the number to type directly, with animated slide transitions
/// and haptic feedback.
class _FlickNumberPicker extends StatefulWidget {
  final String label;
  final double value;
  final double step;
  final double min;
  final double max;
  final bool isInteger;
  final double fontSize;
  final String Function(double) displayFormatter;
  final ValueChanged<double> onChanged;

  const _FlickNumberPicker({
    super.key,
    required this.label,
    required this.value,
    required this.step,
    this.min = 0.0,
    this.max = 999.0,
    this.isInteger = false,
    this.fontSize = 96.0,
    required this.displayFormatter,
    required this.onChanged,
  });

  @override
  State<_FlickNumberPicker> createState() => _FlickNumberPickerState();
}

class _FlickNumberPickerState extends State<_FlickNumberPicker> {
  late double _localValue;
  Timer? _debounceTimer;
  int _lastDeltaDirection = 1; // 1 = up, -1 = down

  // Flick gesture tracking
  double? _dragStartY;
  bool _flickTriggeredThisStroke = false;
  static const double _flickDistanceThreshold = 22.0;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _FlickNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _localValue = widget.value;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _applyStep(int direction) {
    if (direction == 0) return;
    Haptics.selection();

    final delta = direction * widget.step;
    var newVal = _localValue + delta;
    newVal = newVal.clamp(widget.min, widget.max);

    final rounded = widget.isInteger
        ? newVal.roundToDouble()
        : ((newVal * 10).round() / 10.0);

    if (rounded == _localValue) return;

    setState(() {
      _lastDeltaDirection = direction > 0 ? 1 : -1;
      _localValue = rounded;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      widget.onChanged(_localValue);
    });
  }

  void _flushImmediate() {
    _debounceTimer?.cancel();
    widget.onChanged(_localValue);
  }

  Future<void> _typeValue(String formatted) async {
    final ctrl = TextEditingController(text: formatted);
    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set ${widget.label}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(hintText: widget.label),
          onSubmitted: (v) => Navigator.of(ctx).pop(double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (entered != null && entered >= widget.min && entered <= widget.max) {
      setState(() {
        _localValue = entered;
      });
      _flushImmediate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final formatted = widget.displayFormatter(_localValue);

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          if (pointerSignal.scrollDelta.dy < 0) {
            _applyStep(1);
            _flushImmediate();
          } else if (pointerSignal.scrollDelta.dy > 0) {
            _applyStep(-1);
            _flushImmediate();
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (details) {
          _dragStartY = details.localPosition.dy;
          _flickTriggeredThisStroke = false;
        },
        onVerticalDragUpdate: (details) {
          if (_flickTriggeredThisStroke || _dragStartY == null) return;
          final dyDelta = _dragStartY! - details.localPosition.dy;

          if (dyDelta >= _flickDistanceThreshold) {
            _flickTriggeredThisStroke = true;
            _applyStep(1);
          } else if (dyDelta <= -_flickDistanceThreshold) {
            _flickTriggeredThisStroke = true;
            _applyStep(-1);
          }
        },
        onVerticalDragEnd: (details) {
          if (!_flickTriggeredThisStroke) {
            final vy = details.primaryVelocity ?? 0;
            if (vy < -140) {
              _applyStep(1);
            } else if (vy > 140) {
              _applyStep(-1);
            }
          }
          _dragStartY = null;
          _flickTriggeredThisStroke = false;
          _flushImmediate();
        },
        onVerticalDragCancel: () {
          _dragStartY = null;
          _flickTriggeredThisStroke = false;
          _flushImmediate();
        },
        onTap: () => _typeValue(formatted),
        child: Semantics(
          label: widget.label,
          value: formatted,
          increasedValue: widget.displayFormatter(
            (_localValue + widget.step).clamp(widget.min, widget.max),
          ),
          decreasedValue: widget.displayFormatter(
            (_localValue - widget.step).clamp(widget.min, widget.max),
          ),
          onIncrease: () {
            _applyStep(1);
            _flushImmediate();
          },
          onDecrease: () {
            _applyStep(-1);
            _flushImmediate();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: widget.fontSize * 1.1,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) {
                        final inFromBottom = _lastDeltaDirection >= 0;
                        return ClipRect(
                          child: SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: Offset(0.0, inFromBottom ? 0.4 : -0.4),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: FadeTransition(
                              opacity: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: FittedBox(
                        key: ValueKey(formatted),
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatted,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: widget.fontSize,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -widget.fontSize / 24,
                            height: 1.1,
                            color: hx.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: workoutKicker(context, spacing: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
