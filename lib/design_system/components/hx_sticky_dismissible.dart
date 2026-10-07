import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:herculex/design_system/theme/haptics.dart';

/// A swipe-to-dismiss widget that mimics the tactile physics of modern Android
/// notification shades:
/// - Sticky rubber-band drag resistance when pulled backwards.
/// - Crisp haptic tick (`Haptics.selection()`) when crossing the dismiss threshold.
/// - Dynamic icon scale & opacity reaction in the delete background.
/// - Damped spring overshoot bounce-back (`Curves.easeOutBack`) when released before threshold.
/// - Fast ease-out slide-away and smooth vertical size collapse on dismissal.
class HxStickyDismissible extends StatefulWidget {
  final Widget child;
  final Widget? background;
  final VoidCallback onDismissed;
  final Future<bool> Function()? confirmDismiss;
  final DismissDirection direction;
  final double thresholdRatio;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final IconData? icon;

  const HxStickyDismissible({
    super.key,
    required this.child,
    required this.onDismissed,
    this.confirmDismiss,
    this.background,
    this.direction = DismissDirection.endToStart,
    this.thresholdRatio = 0.38,
    this.borderRadius,
    this.margin,
    this.backgroundColor,
    this.icon,
  });

  @override
  State<HxStickyDismissible> createState() => _HxStickyDismissibleState();
}

class _HxStickyDismissibleState extends State<HxStickyDismissible>
    with TickerProviderStateMixin {
  // Horizontal drag / slide offset controller
  late final AnimationController _slideCtrl;
  late Animation<double> _slideAnimation;

  // Vertical size collapse controller (post-slide dismissal)
  late final AnimationController _collapseCtrl;
  late final Animation<double> _sizeAnimation;

  // Background icon pop controller
  late final AnimationController _iconPopCtrl;
  late final Animation<double> _iconPopScale;

  double _dragOffset = 0.0;
  bool _isPastThreshold = false;
  bool _isDismissing = false;
  double _cardWidth = 360.0;

  @override
  void initState() {
    super.initState();

    _slideCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          if (!_isDismissing) {
            setState(() {
              _dragOffset = _slideAnimation.value;
            });
          }
        });

    _slideAnimation = const AlwaysStoppedAnimation(0.0);

    _collapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _sizeAnimation = CurvedAnimation(
      parent: _collapseCtrl,
      curve: Curves.easeInOutCubic,
    );

    _iconPopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _iconPopScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_iconPopCtrl);
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _collapseCtrl.dispose();
    _iconPopCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    if (_isDismissing) return;
    _slideCtrl.stop();
    _cardWidth = context.size?.width ?? 360.0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;

    final dx = details.delta.dx;
    double newOffset = _dragOffset;

    if (widget.direction == DismissDirection.endToStart) {
      // Swiping left (dx < 0) is the dismiss action
      if (dx < 0 || newOffset < 0) {
        newOffset += dx;
      } else {
        // Rubber-band resistance to the right
        newOffset += dx * 0.18;
        newOffset = math.min(newOffset, 28.0);
      }
    } else if (widget.direction == DismissDirection.startToEnd) {
      // Swiping right (dx > 0) is the dismiss action
      if (dx > 0 || newOffset > 0) {
        newOffset += dx;
      } else {
        // Rubber-band resistance to the left
        newOffset += dx * 0.18;
        newOffset = math.max(newOffset, -28.0);
      }
    } else {
      newOffset += dx;
    }

    final threshold = _cardWidth * widget.thresholdRatio;
    final past = newOffset.abs() >= threshold;

    if (past && !_isPastThreshold) {
      // Haptic tick when crossing the dismiss threshold!
      Haptics.selection();
      _iconPopCtrl.forward(from: 0.0);
    } else if (!past && _isPastThreshold) {
      _iconPopCtrl.reverse();
    }

    setState(() {
      _dragOffset = newOffset;
      _isPastThreshold = past;
    });
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_isDismissing) return;

    final velocity = details.primaryVelocity ?? 0.0;
    final threshold = _cardWidth * widget.thresholdRatio;

    bool shouldDismiss = false;
    if (widget.direction == DismissDirection.endToStart) {
      shouldDismiss = (_dragOffset <= -threshold) || (velocity < -650);
    } else if (widget.direction == DismissDirection.startToEnd) {
      shouldDismiss = (_dragOffset >= threshold) || (velocity > 650);
    } else {
      shouldDismiss =
          (_dragOffset.abs() >= threshold) || (velocity.abs() > 650);
    }

    if (shouldDismiss) {
      if (widget.confirmDismiss != null) {
        final confirmed = await widget.confirmDismiss!();
        if (!confirmed) {
          _snapBack();
          return;
        }
      }
      _dismiss(velocity);
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    _slideCtrl.stop();
    _isPastThreshold = false;
    _iconPopCtrl.reverse();

    _slideAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: Curves.easeOutBack, // Sticky spring bounce overshoot
      ),
    );

    _slideCtrl.duration = const Duration(milliseconds: 280);
    _slideCtrl.forward(from: 0.0);
  }

  void _dismiss(double velocity) {
    setState(() {
      _isDismissing = true;
    });

    Haptics.light();

    final targetOffset = widget.direction == DismissDirection.startToEnd
        ? _cardWidth + 40.0
        : -_cardWidth - 40.0;

    _slideAnimation = Tween<double>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _slideCtrl.duration = const Duration(milliseconds: 180);
    _slideCtrl.forward(from: 0.0).then((_) {
      if (!mounted) return;
      // Animate vertical size collapse to 0
      _collapseCtrl.forward().then((_) {
        if (mounted) {
          widget.onDismissed();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissing && _collapseCtrl.isCompleted) {
      return const SizedBox.shrink();
    }

    final threshold = _cardWidth * widget.thresholdRatio;
    final progress = (_dragOffset.abs() / threshold).clamp(0.0, 1.0);
    final isLeftSwipe = _dragOffset < 0;

    final defaultRadius = widget.borderRadius ?? BorderRadius.circular(16);
    final bgColor =
        widget.backgroundColor ?? Colors.redAccent.withValues(alpha: 0.90);
    final iconData = widget.icon ?? Icons.delete_rounded;

    final backgroundWidget =
        widget.background ??
        Container(
          alignment: isLeftSwipe ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: defaultRadius,
          ),
          child: AnimatedBuilder(
            animation: _iconPopCtrl,
            builder: (context, _) {
              final scale = _isPastThreshold
                  ? _iconPopScale.value
                  : (0.85 + 0.15 * progress);
              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: (0.4 + 0.6 * progress).clamp(0.0, 1.0),
                  child: Icon(iconData, color: Colors.white, size: 22),
                ),
              );
            },
          ),
        );

    Widget content = SizeTransition(
      sizeFactor: Tween<double>(begin: 1.0, end: 0.0).animate(_sizeAnimation),
      axis: Axis.vertical,
      child: Padding(
        padding: widget.margin ?? EdgeInsets.zero,
        child: Stack(
          children: [
            // Background reveal
            if (_dragOffset != 0.0 || _isDismissing)
              Positioned.fill(child: backgroundWidget),
            // Foreground sliding child
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _snapBack,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
