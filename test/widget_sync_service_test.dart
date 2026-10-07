import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/services/platform/widget_sync_service.dart';

/// Payload contract between [WidgetSyncService] and the Android widget
/// channel handler in MainActivity.kt, which stores these for the
/// home-screen widget providers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ams.herculex/widget');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'syncRecovery sends the most fatigued muscles as name/score maps',
    () async {
      await WidgetSyncService().syncRecovery(
        scorePct: 78,
        muscles: const [('Quads', 42), ('Hamstrings', 58)],
      );

      expect(calls.single.method, 'syncRecovery');
      expect(calls.single.arguments, {
        'scorePct': 78,
        'muscles': [
          {'name': 'Quads', 'score': 42},
          {'name': 'Hamstrings', 'score': 58},
        ],
      });
    },
  );

  test('syncFasting sends epoch millis and nulls when idle', () async {
    final start = DateTime.utc(2026, 10, 7, 6, 30);
    await WidgetSyncService().syncFasting(
      startedAt: start,
      targetSeconds: 16 * 3600,
      planLabel: '16:8',
    );
    await WidgetSyncService().syncFasting(
      startedAt: null,
      targetSeconds: null,
      planLabel: null,
    );

    expect(calls[0].arguments, {
      'startedAtMs': start.millisecondsSinceEpoch,
      'targetSeconds': 16 * 3600,
      'planLabel': '16:8',
    });
    expect(calls[1].arguments, {
      'startedAtMs': null,
      'targetSeconds': null,
      'planLabel': null,
    });
  });

  test('syncTheme sends the mode and both palettes as ARGB ints', () async {
    await WidgetSyncService().syncTheme(
      mode: ThemeMode.system,
      dark: HxColors.of(Brightness.dark, AppColorTheme.pinky),
      light: HxColors.of(Brightness.light, AppColorTheme.pinky),
    );

    final args = (calls.single.arguments as Map).cast<String, dynamic>();
    expect(args['mode'], 'system');
    final dark = (args['dark'] as Map).cast<String, int>();
    final light = (args['light'] as Map).cast<String, int>();
    expect(dark['primary'], HxColors.pinkyDark.primary.toARGB32());
    expect(
      light['surface'],
      HxColors.pinkyLight.surfaceContainerLowest.toARGB32(),
    );
    // Every key HxWidgetPalette.fromJson reads.
    expect(dark.keys, unorderedEquals(light.keys));
    expect(
      dark.keys,
      containsAll(<String>[
        'surface',
        'surfaceVariant',
        'outlineVariant',
        'onSurface',
        'secondary',
        'primary',
        'onPrimary',
        'kcal',
        'protein',
        'carbs',
        'fat',
        'success',
        'warning',
        'danger',
        'recovery',
        'fasting',
        'nutrition',
      ]),
    );
  });

  test(
    'syncWidgetData sends key + payload and skips unchanged payloads',
    () async {
      final sync = WidgetSyncService();
      await sync.syncWidgetData('volume', {'sets': 64});
      await sync.syncWidgetData('volume', {'sets': 64});
      await sync.syncWidgetData('volume', {'sets': 65});
      await sync.syncWidgetData('volume', null);

      expect(calls.map((c) => c.arguments), [
        {
          'key': 'volume',
          'data': {'sets': 64},
        },
        {
          'key': 'volume',
          'data': {'sets': 65},
        },
        {'key': 'volume', 'data': null},
      ]);
    },
  );
}
