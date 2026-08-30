import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/error/app_error_handler.dart';
import 'package:herculex/core/error/app_error_view.dart';
import 'package:herculex/core/error/error_log.dart';

/// The app shipped with **no** global error handling at all — a repo-wide grep
/// for `ErrorWidget.builder`, `FlutterError.onError`,
/// `PlatformDispatcher.onError` and `runZonedGuarded` returned zero matches.
/// A throw in `build` was therefore the full-screen red `ErrorWidget` in debug
/// and a silent grey box in release, with nothing recorded anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ErrorLog.instance.clear();
    AppErrorHandler.resetForTest();
  });

  group('ErrorLog', () {
    test('keeps newest first and caps at capacity', () {
      for (var i = 0; i < ErrorLog.capacity + 10; i++) {
        ErrorLog.instance.record(Exception('boom $i'), source: 'test');
      }

      final records = ErrorLog.instance.records;
      expect(records, hasLength(ErrorLog.capacity));
      expect(records.first.summary, contains('boom ${ErrorLog.capacity + 9}'));
      // The 10 oldest were evicted by the ring buffer.
      expect(records.last.summary, contains('boom 10'));
    });

    test('records only the first line of a multi-line exception', () {
      ErrorLog.instance.record(
        'first line\nsecond line\nthird line',
        source: 'test',
      );
      expect(ErrorLog.instance.records.single.summary, 'first line');
    });

    test('survives an error object whose toString throws', () {
      // The error path must never escalate a handled error into an unhandled
      // one.
      ErrorLog.instance.record(_HostileError(), source: 'test');
      expect(ErrorLog.instance.length, 1);
      expect(ErrorLog.instance.records.single.summary, contains('threw'));
    });

    test('bumps its revision so a listening view rebuilds', () {
      final before = ErrorLog.instance.revision.value;
      ErrorLog.instance.record(Exception('x'), source: 'test');
      expect(ErrorLog.instance.revision.value, greaterThan(before));
    });
  });

  testWidgets('a throwing widget renders the fallback instead of the red box', (
    tester,
  ) async {
    // flutter_test asserts `ErrorWidget.builder` is back to the exact original
    // reference, and it checks *before* `addTearDown` callbacks run — so the
    // restore has to happen inside the test body.
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    final originalOnError = FlutterError.onError;
    try {
      AppErrorHandler.install();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _Exploding())),
      );

      expect(
        find.byType(AppErrorView),
        findsOneWidget,
        reason: 'ErrorWidget.builder must swap in the branded fallback',
      );
      // The throw is expected — consume it so the test does not fail on it.
      expect(tester.takeException(), isA<StateError>());
      // ...and the same failure must have been captured for the admin log.
      expect(
        ErrorLog.instance.records.any((r) => r.summary.contains('kaboom')),
        isTrue,
        reason: 'FlutterError.onError must funnel build failures into ErrorLog',
      );
    } finally {
      ErrorWidget.builder = originalErrorWidgetBuilder;
      FlutterError.onError = originalOnError;
    }
  });

  testWidgets('the fallback renders with no Theme or Directionality above it', (
    tester,
  ) async {
    // ErrorWidget.builder replaces an arbitrary widget at an arbitrary point
    // in the tree, so the fallback can land above MaterialApp entirely. If it
    // needed an inherited Theme or Directionality it would throw from inside
    // the error path and recurse.
    await tester.pumpWidget(
      const Center(child: AppErrorView(message: 'bare tree')),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AppErrorView), findsOneWidget);
  });
}

class _Exploding extends StatelessWidget {
  const _Exploding();

  @override
  Widget build(BuildContext context) => throw StateError('kaboom');
}

class _HostileError {
  @override
  String toString() => throw StateError('toString exploded');
}
