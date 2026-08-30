import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_error_view.dart';
import 'error_log.dart';

/// Installs the app's global error handling.
///
/// Before this existed the app had none — no `ErrorWidget.builder`, no
/// `FlutterError.onError`, no `PlatformDispatcher.onError` — so any exception
/// thrown during `build` painted the full-screen red `ErrorWidget` in debug and
/// a **silent grey box** in release, and every dropped `Future` (the 20s sync
/// timer, the fire-and-forget platform-channel calls) vanished without a trace.
///
/// Three hooks, three distinct error sources:
///
/// * [FlutterError.onError] — errors raised *by the framework*, i.e. anything
///   thrown inside `build`/`layout`/`paint`.
/// * [PlatformDispatcher.onError] — uncaught *asynchronous* errors that reach
///   the root zone.
/// * [ErrorWidget.builder] — what gets *rendered* where a failed subtree was.
///
/// All three funnel into [ErrorLog] so the admin dashboard can read them back.
///
/// Deliberately **not** `runZonedGuarded`: `main` calls
/// `WidgetsFlutterBinding.ensureInitialized()` before several `await`s, and
/// binding-initialised-in-a-different-zone-than-runApp is its own class of
/// startup failure. Since Flutter 3.3 `PlatformDispatcher.onError` catches
/// everything that reaches the root zone, which is exactly the coverage the
/// zone guard would have added.
abstract final class AppErrorHandler {
  const AppErrorHandler._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      ErrorLog.instance.record(
        details.exception,
        source: 'flutter',
        stack: details.stack,
        details: details.context?.toString() ?? details.library,
      );
      // Keep the framework's formatted console dump — losing it would make
      // local debugging strictly worse than before.
      if (previousOnError != null) {
        previousOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorLog.instance.record(error, source: 'platform', stack: stack);
      if (!kReleaseMode) {
        debugPrint('[AppErrorHandler] $error');
        debugPrintStack(stackTrace: stack);
      }
      // Handled: returning false re-throws into the root zone, which is what
      // used to terminate the isolate on some paths.
      return true;
    };

    ErrorWidget.builder = (details) {
      // FlutterError.onError has already logged this one; recording it again
      // here would double every build failure in the log.
      return AppErrorView(message: details.exceptionAsString());
    };
  }

  /// Test seam — lets a test restore Flutter's defaults between cases.
  @visibleForTesting
  static void resetForTest() => _installed = false;
}
