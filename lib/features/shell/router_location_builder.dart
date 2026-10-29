import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Rebuilds with the location of the screen on top of [router]'s stack, on
/// every push, pop and `go`.
///
/// Meant for widgets above the navigator (the rail's scope), which cannot ask
/// `GoRouterState.of(context)`. The router delegate also notifies while the
/// framework is mid-build — the very first redirect does — where `setState`
/// is an error, so a notification then is applied after the frame.
class RouterLocationBuilder extends StatefulWidget {
  const RouterLocationBuilder({
    super.key,
    required this.router,
    required this.builder,
  });

  final GoRouter router;
  final Widget Function(BuildContext context, String location) builder;

  @override
  State<RouterLocationBuilder> createState() => _RouterLocationBuilderState();
}

class _RouterLocationBuilderState extends State<RouterLocationBuilder> {
  late String _location = _read(widget.router);

  static String _read(GoRouter router) =>
      router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ??
      '';

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void didUpdateWidget(RouterLocationBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRouteChanged);
      widget.router.routerDelegate.addListener(_onRouteChanged);
      _location = _read(widget.router);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => _refresh());
    } else {
      _refresh();
    }
  }

  void _refresh() {
    if (!mounted) return;
    final location = _read(widget.router);
    if (location != _location) setState(() => _location = location);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _location);
}
