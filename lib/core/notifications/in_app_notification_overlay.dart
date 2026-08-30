import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/haptics.dart';
import 'in_app_notification_controller.dart';
import 'in_app_notification_model.dart';

/// Wraps any widget tree (e.g. root [MaterialApp] builder) to host floating
/// top-dropping in-app notifications.
class InAppNotificationHost extends ConsumerWidget {
  final Widget child;

  const InAppNotificationHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inAppNotificationControllerProvider);

    return Stack(
      children: [
        child,
        if (state.current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              type: MaterialType.transparency,
              child: _InAppNotificationBanner(
                key: ValueKey(state.current!.id),
                item: state.current!,
                isDismissing: state.isDismissing,
                onDismiss: () => ref
                    .read(inAppNotificationControllerProvider.notifier)
                    .dismiss(),
              ),
            ),
          ),
      ],
    );
  }
}

const _kCircleSize = 38.0;
const _kPillHeight = 56.0;
const _kPillPadding = 9.0;
const _kContentGap = 10.0;
const _kMinWidth =
    _kCircleSize + _kPillPadding * 2; // == 56.0, collapsed circle
// height:1.0 keeps the two text lines within the pill's fixed 38px content
// area (56px pill height minus 9px top/bottom padding) despite these
// variable fonts' generous default line-height metrics.
const _kLabelStyle = TextStyle(
  fontFamily: AppTheme.fontBody,
  fontWeight: FontWeight.w600,
  fontSize: 11.5,
  letterSpacing: 0.1,
  height: 1.0,
  color: Color(0xFF94A3B8),
  decoration: TextDecoration.none,
);
const _kValueStyle = TextStyle(
  fontFamily: AppTheme.fontDisplay,
  fontWeight: FontWeight.w700,
  fontSize: 17,
  letterSpacing: -0.3,
  height: 1.0,
  color: Colors.white,
  decoration: TextDecoration.none,
);
const _kDeltaBaseStyle = TextStyle(
  fontFamily: AppTheme.fontBody,
  fontWeight: FontWeight.w700,
  fontSize: 11.5,
  height: 1.0,
  decoration: TextDecoration.none,
);

class _InAppNotificationBanner extends StatefulWidget {
  final InAppNotificationItem item;
  final bool isDismissing;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    super.key,
    required this.item,
    required this.isDismissing,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with TickerProviderStateMixin {
  // Entrance: drop + settle/expand + content reveal, played once on mount.
  late final AnimationController _enterCtrl;
  late final Animation<double> _dropY;
  late final Animation<double> _dropOpacity;
  late final Animation<double> _circleScale;
  late final Animation<double> _widthExpand;
  late final Animation<double> _contentOpacityIn;
  late final Animation<double> _contentSlideIn;

  // Exit: collapse width, then fly off-screen. Started when isDismissing flips.
  late final AnimationController _exitCtrl;
  late final Animation<double> _widthCollapse;
  late final Animation<double> _contentOpacityOut;
  late final Animation<double> _exitY;
  late final Animation<double> _exitOpacity;

  double _dragOffsetY = 0.0;
  double? _targetWidth;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(
      vsync: this,
      duration: kAchievementEnterDuration, // 1160ms
    );
    _dropY = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.0, 480 / 1160, curve: Curves.easeOutCubic),
    );
    _dropOpacity = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.0, 90 / 1160),
    );
    _circleScale = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(40 / 1160, 520 / 1160, curve: Curves.easeOutCubic),
    );
    _widthExpand = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(600 / 1160, 1080 / 1160, curve: Curves.easeOutExpo),
    );
    _contentOpacityIn = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(
        800 / 1160,
        1090 / 1160,
        curve: Curves.easeOutCubic,
      ),
    );
    _contentSlideIn = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(
        800 / 1160,
        1120 / 1160,
        curve: Curves.easeOutCubic,
      ),
    );

    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _widthCollapse = CurvedAnimation(
      parent: _exitCtrl,
      curve: const Interval(0.0, 240 / 560, curve: Curves.easeInCubic),
    );
    _contentOpacityOut = CurvedAnimation(
      parent: _exitCtrl,
      curve: const Interval(0.0, 110 / 560),
    );
    _exitY = CurvedAnimation(
      parent: _exitCtrl,
      curve: const Interval(240 / 560, 1.0, curve: Curves.easeInCubic),
    );
    _exitOpacity = CurvedAnimation(
      parent: _exitCtrl,
      curve: const Interval(240 / 560, 1.0, curve: Curves.easeInCubic),
    );

    _enterCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant _InAppNotificationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDismissing && !oldWidget.isDismissing) {
      _exitCtrl.forward();
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  double _measureTargetWidth(double maxAvailable) {
    final labelPainter = TextPainter(
      text: TextSpan(text: widget.item.label, style: _kLabelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final valueRowSpans = <InlineSpan>[
      TextSpan(text: widget.item.value, style: _kValueStyle),
    ];
    if (widget.item.delta != null) {
      valueRowSpans.add(const TextSpan(text: '  ')); // approximates the 7px gap
      valueRowSpans.add(
        TextSpan(
          text: widget.item.delta,
          style: _kDeltaBaseStyle.copyWith(color: widget.item.primaryColor),
        ),
      );
    }
    final valueRowPainter = TextPainter(
      text: TextSpan(children: valueRowSpans),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final contentWidth = math.max(labelPainter.width, valueRowPainter.width);
    final natural =
        _kCircleSize +
        _kPillPadding * 2 +
        _kContentGap +
        contentWidth +
        6.0; // trailing content padding

    return natural.clamp(_kMinWidth, maxAvailable);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = math.max(mediaQuery.padding.top, 14.0);
    final screenWidth = mediaQuery.size.width;

    _targetWidth ??= _measureTargetWidth(screenWidth - 32.0);
    final targetWidth = _targetWidth!;

    // Spec values (-104 / 54 / -120) assume a ~48px status bar; translate them
    // relative to this device's actual safe-area inset instead of hardcoding.
    final restY = topPadding + 6.0;
    final dropStartY = restY - 158.0; // -104 -> 54 is a 158px travel
    final exitEndY = restY - 174.0; // 54 -> -120 is a 174px travel

    final primaryColor = widget.item.primaryColor;

    return AnimatedBuilder(
      animation: Listenable.merge([_enterCtrl, _exitCtrl]),
      builder: (context, _) {
        final exiting = widget.isDismissing;

        final width = exiting
            ? _lerp(targetWidth, _kMinWidth, _widthCollapse.value)
            : _lerp(_kMinWidth, targetWidth, _widthExpand.value);

        final contentOpacity = exiting
            ? _lerp(1.0, 0.0, _contentOpacityOut.value)
            : _contentOpacityIn.value;

        final circleScale = exiting ? 1.0 : _lerp(0.6, 1.0, _circleScale.value);

        final y = exiting
            ? _lerp(restY, exitEndY, _exitY.value)
            : _lerp(dropStartY, restY, _dropY.value);

        final wrapOpacity = exiting
            ? _lerp(1.0, 0.0, _exitOpacity.value)
            : _dropOpacity.value;

        final contentDx = exiting
            ? 0.0
            : _lerp(-12.0, 0.0, _contentSlideIn.value);

        // Gate on opacity, not width: during exit the pill's width collapses
        // (0-240ms) slower than content fades out (0-110ms), so a width-based
        // gate would keep the content Row mounted - and laid out into an
        // already-too-narrow Expanded - after it's invisible, overflowing.
        final showContent = contentOpacity > 0.01;

        return Transform.translate(
          offset: Offset(0, y + _dragOffsetY),
          child: Opacity(
            opacity: wrapOpacity.clamp(0.0, 1.0),
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null &&
                      details.primaryDelta! < 0) {
                    setState(() {
                      _dragOffsetY += details.primaryDelta!;
                    });
                  }
                },
                onVerticalDragEnd: (details) {
                  if (_dragOffsetY < -18 ||
                      (details.primaryVelocity ?? 0) < -200) {
                    Haptics.selection();
                    widget.onDismiss();
                  } else {
                    setState(() {
                      _dragOffsetY = 0;
                    });
                  }
                },
                onTap: () {
                  Haptics.light();
                  widget.item.onTap?.call();
                  widget.onDismiss();
                },
                child: SizedBox(
                  width: width,
                  height: _kPillHeight,
                  // DecoratedBox (not Container) so the border's stroke width
                  // isn't silently added on top of the padding below -
                  // Container merges decoration.padding into its own padding,
                  // which shrank the content box below the circle's size.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161E2E),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF2B374E),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(4, 9, 19, 0.55),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(_kPillPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Transform.scale(
                            scale: circleScale,
                            child: _TrophyCircle(
                              icon: widget.item.icon,
                              color: primaryColor,
                            ),
                          ),
                          if (showContent) ...[
                            const SizedBox(width: _kContentGap),
                            Expanded(
                              child: ClipRect(
                                child: Opacity(
                                  opacity: contentOpacity.clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(contentDx, 0),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.item.label,
                                          style: _kLabelStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 1),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.item.value,
                                              style: _kValueStyle,
                                              maxLines: 1,
                                            ),
                                            if (widget.item.delta != null) ...[
                                              const SizedBox(width: 7),
                                              Text(
                                                widget.item.delta!,
                                                style: _kDeltaBaseStyle
                                                    .copyWith(
                                                      color: primaryColor,
                                                    ),
                                                maxLines: 1,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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

/// The flat-fill circular badge containing the achievement icon.
class _TrophyCircle extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _TrophyCircle({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kCircleSize,
      height: _kCircleSize,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Center(
        child: Icon(icon, color: const Color(0xFF091322), size: 21),
      ),
    );
  }
}
