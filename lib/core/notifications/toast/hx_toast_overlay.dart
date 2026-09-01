import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/haptics.dart';
import 'hx_toast_controller.dart';
import 'hx_toast_model.dart';

/// Wraps any widget tree (e.g. root [MaterialApp] builder) to host the
/// centered "squircle" save/sync confirmation toast. Independent of
/// [InAppNotificationHost] (the achievement/PR pill HUD) — the two overlays
/// never share state and can, in the rare case both fire at once, be visible
/// together without conflict since one drops from the top and this one sits
/// centered.
class HxToastHost extends ConsumerWidget {
  final Widget child;

  const HxToastHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hxToastControllerProvider);

    return Stack(
      children: [
        child,
        if (state.current != null)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: _HxToastCard(
                  key: ValueKey(state.current!.id),
                  item: state.current!,
                  isDismissing: state.isDismissing,
                  onDismiss: () =>
                      ref.read(hxToastControllerProvider.notifier).dismiss(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const _kCardWidth = 216.0;
const _kCardRadius = 54.0;
const _kIconSize = 54.0;
const _kEnterDuration = Duration(milliseconds: 520);
const _kExitDuration = Duration(milliseconds: 260);
const _kTextDelayMs = 180;
const _kTextDurationMs = 420;
const _kFlexDuration = Duration(milliseconds: 900);

class _HxToastCard extends StatefulWidget {
  final HxToastItem item;
  final bool isDismissing;
  final VoidCallback onDismiss;

  const _HxToastCard({
    super.key,
    required this.item,
    required this.isDismissing,
    required this.onDismiss,
  });

  @override
  State<_HxToastCard> createState() => _HxToastCardState();
}

class _HxToastCardState extends State<_HxToastCard>
    with TickerProviderStateMixin {
  // Entrance: pop in (scale + opacity), then the text rises/fades in with a
  // short delay. Played once on mount.
  late final AnimationController _enterCtrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _textReveal;

  // Exit: fade + settle down. Started when isDismissing flips.
  late final AnimationController _exitCtrl;

  // Icon "flex" loop: subtle scale/rotate wiggle, repeats while visible.
  late final AnimationController _flexCtrl;
  late final Animation<double> _flexScale;
  late final Animation<double> _flexRotation;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(vsync: this, duration: _kEnterDuration);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.72,
          end: 1.04,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.04,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
    ]).animate(_enterCtrl);
    _opacity = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );

    final enterMs = _kEnterDuration.inMilliseconds;
    final textStart = (_kTextDelayMs / enterMs).clamp(0.0, 1.0);
    final textEnd = ((_kTextDelayMs + _kTextDurationMs) / enterMs).clamp(
      0.0,
      1.0,
    );
    _textReveal = CurvedAnimation(
      parent: _enterCtrl,
      curve: Interval(
        textStart,
        textEnd < textStart ? textStart : textEnd,
        curve: Curves.easeOut,
      ),
    );

    _exitCtrl = AnimationController(vsync: this, duration: _kExitDuration);

    _flexCtrl = AnimationController(vsync: this, duration: _kFlexDuration);
    _flexScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_flexCtrl);
    _flexRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: -3.0,
          end: 3.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 3.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: -3.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_flexCtrl);

    _enterCtrl.forward();
    _flexCtrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _HxToastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDismissing && !oldWidget.isDismissing) {
      _flexCtrl.stop();
      _exitCtrl.forward();
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _exitCtrl.dispose();
    _flexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    const base = Color(0xFF161E2E);

    return AnimatedBuilder(
      animation: Listenable.merge([_enterCtrl, _exitCtrl, _flexCtrl]),
      builder: (context, _) {
        final exiting = widget.isDismissing;
        final exitT = Curves.easeIn.transform(_exitCtrl.value);

        final scale = exiting ? _lerp(1.0, 0.85, exitT) : _scale.value;
        final opacity = (exiting ? _lerp(1.0, 0.0, exitT) : _opacity.value)
            .clamp(0.0, 1.0);
        final textOpacity = exiting
            ? opacity
            : _textReveal.value.clamp(0.0, 1.0);
        final textDy = exiting ? 0.0 : _lerp(8.0, 0.0, _textReveal.value);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: GestureDetector(
              onTap: () {
                Haptics.light();
                item.onTap?.call();
                widget.onDismiss();
              },
              child: Container(
                width: _kCardWidth,
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.58],
                    colors: [
                      Color.alphaBlend(
                        item.accentColor.withValues(alpha: 0.16),
                        base,
                      ),
                      base,
                    ],
                  ),
                  border: Border.all(
                    color: item.accentColor.withValues(alpha: 0.32),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(4, 9, 19, 0.65),
                      blurRadius: 60,
                      offset: Offset(0, 24),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Center(
                        child: Transform.rotate(
                          angle: _flexRotation.value * math.pi / 180,
                          child: Transform.scale(
                            scale: _flexScale.value,
                            child: Icon(
                              item.icon,
                              size: _kIconSize,
                              color: item.accentColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: textOpacity,
                      child: Transform.translate(
                        offset: Offset(0, textDy),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                height: 1.2,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 13,
                                height: 1.35,
                                color: Color(0xFF94A3B8),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
