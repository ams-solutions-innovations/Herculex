import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

// Shared pieces of the full-screen workout flow: active set, rest, RPE and
// the done screens all use the same header controls and the same big
// bottom call to action.

/// Linked-exercise accent (supersets, tri-sets, giant sets). The palette has
/// no cyan of its own, and this one is already what classic mode uses.
const supersetCyan = Color(0xFF26C6DA);

/// Dark ink for text and icons on a success-green button (the finish step),
/// where white on green reads poorly.
const successInk = Color(0xFF04210F);

/// Small all-caps label above a value or heading (`SET 2 OF 4`, `UP NEXT`).
TextStyle workoutKicker(
  BuildContext context, {
  Color? color,
  double size = 11,
  double spacing = 1.4,
}) => TextStyle(
  fontFamily: Theme.of(context).textTheme.labelSmall?.fontFamily,
  color: color ?? context.hx.secondary,
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: spacing,
);

/// The bordered round control used in the workout headers (close, back,
/// previous / next exercise).
class WorkoutCircleButton extends StatelessWidget {
  const WorkoutCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 40,
    this.iconSize = 22,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: hx.surfaceContainer,
        shape: CircleBorder(side: BorderSide(color: hx.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: onTap == null ? hx.outline : (iconColor ?? hx.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width 66 dp call to action at the bottom of each workout step, lit
/// from above with a soft glow underneath in its own colour.
class WorkoutHeroButton extends StatelessWidget {
  const WorkoutHeroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.color,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  /// Base colour; defaults to the brand colour.
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final base = color ?? hx.primary;
    final fg = foreground ?? hx.onPrimary;
    return Container(
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(base, Colors.white, 0.14)!, base],
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 26, color: fg),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.labelLarge?.fontFamily,
                    color: fg,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 24, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `42:18` / `1:04:09` since [startedAt], ticking once a second on its own so
/// the workout header stays live between rest timers.
class WorkoutElapsedText extends ConsumerStatefulWidget {
  const WorkoutElapsedText({super.key, required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  /// Same format the header uses, for screens that only need the string.
  static String format(Duration elapsed) {
    final s = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  @override
  ConsumerState<WorkoutElapsedText> createState() => _WorkoutElapsedTextState();
}

class _WorkoutElapsedTextState extends ConsumerState<WorkoutElapsedText> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).now();
    return Text(
      WorkoutElapsedText.format(now.difference(widget.startedAt)),
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Small pulsing dot that marks something as live (a running workout, an
/// experiment in its change phase).
class LivePulseDot extends StatefulWidget {
  const LivePulseDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 1.0,
        end: 0.25,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
