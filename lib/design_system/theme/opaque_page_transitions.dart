import 'package:flutter/material.dart';

/// Android predictive back for an app whose Scaffolds are transparent.
///
/// Herculex paints one background gradient behind the whole Navigator and
/// leaves every Scaffold transparent. That is invisible with a normal route
/// transition, but predictive back shrinks the outgoing page while the
/// previous one shows underneath, so two transparent pages read through each
/// other. Giving each page its own opaque copy of the gradient fixes that. The
/// gradient is screen-sized in both places, so a page at rest looks identical.
class OpaquePredictiveBackTransitionsBuilder extends PageTransitionsBuilder {
  const OpaquePredictiveBackTransitionsBuilder({required this.gradient});

  /// Fully opaque; the same gradient the app paints behind the Navigator.
  final Gradient gradient;

  static const PageTransitionsBuilder _inner =
      PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: child,
      ),
    );
  }
}
