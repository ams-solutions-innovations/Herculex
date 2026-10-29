import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/presentation/widgets/fullscreen_workout_kit.dart';

class RpeOption {
  final int valueX10;
  final String label;
  final String rir;
  final String description;
  final Color color;

  const RpeOption({
    required this.valueX10,
    required this.label,
    required this.rir,
    required this.description,
    required this.color,
  });
}

/// Full-screen RPE selection shown when a set is completed or edited: one big
/// number, a draggable effort scale under the thumb, and a single save.
class FullScreenRpePicker extends ConsumerStatefulWidget {
  final String exerciseName;
  final String setLabel;
  final String? performanceSubtitle;
  final int? initialRpeX10;

  const FullScreenRpePicker({
    super.key,
    required this.exerciseName,
    required this.setLabel,
    this.performanceSubtitle,
    this.initialRpeX10,
  });

  /// Hardest first. The scale on screen reads the other way round.
  static const List<RpeOption> options = [
    RpeOption(
      valueX10: 100,
      label: '10',
      rir: '0 RIR',
      description: 'Maximum effort · absolute limit',
      color: Color(0xFFEF4444),
    ),
    RpeOption(
      valueX10: 95,
      label: '9.5',
      rir: '0–1 RIR',
      description: 'Extreme · maybe 1 more with breakdown',
      color: Color(0xFFF97316),
    ),
    RpeOption(
      valueX10: 90,
      label: '9',
      rir: '1 RIR',
      description: 'Heavy · definitely 1 more clean rep',
      color: Color(0xFFFB923C),
    ),
    RpeOption(
      valueX10: 85,
      label: '8.5',
      rir: '1–2 RIR',
      description: 'Hard · solid set, 1 to 2 reps left',
      color: Color(0xFFF59E0B),
    ),
    RpeOption(
      valueX10: 80,
      label: '8',
      rir: '2 RIR',
      description: 'Challenging · good speed, 2 reps left',
      color: Color(0xFFEAB308),
    ),
    RpeOption(
      valueX10: 75,
      label: '7.5',
      rir: '2–3 RIR',
      description: 'Moderate-heavy · fast bar speed',
      color: Color(0xFF84CC16),
    ),
    RpeOption(
      valueX10: 70,
      label: '7',
      rir: '3 RIR',
      description: 'Moderate effort · 3 reps in reserve',
      color: Color(0xFF22C55E),
    ),
    RpeOption(
      valueX10: 65,
      label: '6.5',
      rir: '3–4 RIR',
      description: 'Light-moderate · 3 to 4 reps in reserve',
      color: Color(0xFF14B8A6),
    ),
    RpeOption(
      valueX10: 60,
      label: '6',
      rir: '4+ RIR',
      description: 'Light effort · warm-up speed, very easy',
      color: Color(0xFF06B6D4),
    ),
    RpeOption(
      valueX10: 50,
      label: '<6',
      rir: '5+ RIR',
      description: 'Minimal effort · light warm-up',
      color: Color(0xFF94A3B8),
    ),
  ];

  /// Shows the full-screen RPE selector.
  /// Returns the chosen `rpeX10` (e.g. 85), `-1` if cleared, or `null` if dismissed/skipped.
  static Future<int?> show(
    BuildContext context, {
    required String exerciseName,
    required String setLabel,
    String? performanceSubtitle,
    int? initialRpeX10,
  }) {
    return showGeneralDialog<int?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'RPE Selection',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => FullScreenRpePicker(
        exerciseName: exerciseName,
        setLabel: setLabel,
        performanceSubtitle: performanceSubtitle,
        initialRpeX10: initialRpeX10,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  ConsumerState<FullScreenRpePicker> createState() =>
      _FullScreenRpePickerState();
}

class _FullScreenRpePickerState extends ConsumerState<FullScreenRpePicker> {
  /// Easiest first — the order the scale reads left to right.
  static final _options = FullScreenRpePicker.options.reversed.toList();

  /// Nearest scale step to the set's logged, planned or target RPE; a
  /// challenging 8 when there is nothing to go on.
  late int _index = () {
    final initial = widget.initialRpeX10;
    if (initial == null) return 5;
    var best = 0;
    for (var i = 1; i < _options.length; i++) {
      if ((_options[i].valueX10 - initial).abs() <
          (_options[best].valueX10 - initial).abs()) {
        best = i;
      }
    }
    return best;
  }();

  void _pickAt(double dx, double width) {
    final i = ((dx / width).clamp(0.0, 1.0) * (_options.length - 1)).round();
    if (i == _index) return;
    Haptics.selection();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final restTimer = ref.watch(restTimerProvider);
    final now = ref.watch(clockProvider).now();
    final remainingRest = restTimer.remainingSecondsFrom(now);
    final selected = _options[_index];

    return Scaffold(
      backgroundColor: hx.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Close · resting · skip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  WorkoutCircleButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                  const Spacer(),
                  if (restTimer.isRunning && remainingRest > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: hx.primary.withValues(alpha: 0.14),
                        borderRadius: HxRadius.pillAll,
                        border: Border.all(
                          color: hx.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 15,
                            color: hx.primaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Resting ${remainingRest ~/ 60}:${(remainingRest % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: hx.primaryText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: hx.secondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Which set ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(
                children: [
                  Text(
                    '${widget.setLabel.toUpperCase()} · COMPLETED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.primaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.exerciseName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.displaySmall?.copyWith(fontSize: 22),
                  ),
                  if (widget.performanceSubtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.performanceSubtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hx.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── The answer, big ──
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'HOW HARD WAS IT?',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.tertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          selected.color.withValues(alpha: 0.22),
                          selected.color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 60,
                        vertical: 20,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          selected.label,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 120,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            letterSpacing: -5,
                            color: selected.color,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: selected.color.withValues(alpha: 0.14),
                      borderRadius: HxRadius.pillAll,
                    ),
                    child: Text(
                      selected.rir,
                      style: TextStyle(
                        color: selected.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      selected.description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: hx.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Effort scale ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: _RpeScale(
                options: _options,
                index: _index,
                onPick: _pickAt,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: hx.tertiary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('EASY'), Text('DRAG OR TAP'), Text('MAX')],
                ),
              ),
            ),

            // ── Save ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: SizedBox(
                width: double.infinity,
                height: 62,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: hx.primary,
                    foregroundColor: hx.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () {
                    Haptics.medium();
                    Navigator.of(context).pop(selected.valueX10);
                  },
                  child: Text('Save RPE ${selected.label}'),
                ),
              ),
            ),
            if (widget.initialRpeX10 != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Clear RPE'),
                style: TextButton.styleFrom(foregroundColor: hx.secondary),
                onPressed: () {
                  Haptics.light();
                  Navigator.of(context).pop(-1);
                },
              )
            else
              const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Gradient effort track with a thumb. Dragging or tapping anywhere on it
/// snaps to the nearest scale step.
class _RpeScale extends StatelessWidget {
  const _RpeScale({
    required this.options,
    required this.index,
    required this.onPick,
  });

  final List<RpeOption> options;
  final int index;
  final void Function(double dx, double width) onPick;

  static const _track = [
    Color(0xFF94A3B8),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFFF97316),
    Color(0xFFEF4444),
  ];

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final steps = options.length - 1;
    final fraction = index / steps;
    final selected = options[index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onPick(d.localPosition.dx, width),
              onHorizontalDragStart: (d) => onPick(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => onPick(d.localPosition.dx, width),
              child: SizedBox(
                height: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 22,
                      height: 12,
                      child: Opacity(
                        opacity: 0.35,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: const LinearGradient(colors: _track),
                          ),
                        ),
                      ),
                    ),
                    // The filled part shows the same gradient, cut at the
                    // thumb, so the colour under the thumb is the answer's.
                    Positioned(
                      left: 0,
                      top: 22,
                      height: 12,
                      width: width * fraction,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: width,
                          maxWidth: width,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _track),
                            ),
                            child: SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i <= steps; i++)
                      Positioned(
                        left: width * i / steps - 2,
                        top: 26,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: hx.background.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      left: width * fraction - 18,
                      top: 10,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected.color, width: 6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i <= steps; i++)
                    Positioned(
                      left: width * i / steps - 16,
                      width: 32,
                      child: Text(
                        options[i].label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.displaySmall?.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: i == index ? options[i].color : hx.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
