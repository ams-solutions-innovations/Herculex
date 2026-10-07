import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/services/platform/widget_sync_service.dart';

class _FixedClock implements Clock {
  _FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}

/// Days since 1970-01-01 of 2026-10-07, the date the tests pin the clock to.
const _epochDayOct7 = 20733;

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
      await WidgetSyncService(
        clock: _FixedClock(DateTime(2026, 10, 7, 9)),
      ).syncRecovery(
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
        'epochDay': _epochDayOct7,
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

  test('payloads describing today carry the local epoch day', () async {
    // Late evening: the day number must follow the calendar date, not UTC.
    final sync = WidgetSyncService(
      clock: _FixedClock(DateTime(2026, 10, 7, 23, 59)),
    );
    await sync.syncNutrition(
      baseGoalKcal: 2400,
      foodKcal: 1200,
      exerciseKcal: 300,
      remainingKcal: 1500,
      carbsCurrent: 100,
      carbsTarget: 250,
      fatCurrent: 40,
      fatTarget: 80,
      proteinCurrent: 90,
      proteinTarget: 180,
    );
    await sync.syncMacros(
      carbsCurrent: 100,
      carbsTarget: 250,
      fatCurrent: 40,
      fatTarget: 80,
      proteinCurrent: 90,
      proteinTarget: 180,
    );
    await sync.syncCns(readinessPct: 70, status: 'FRESH');
    await sync.syncRecovery(scorePct: 55);

    expect(calls.map((c) => c.method), [
      'syncNutrition',
      'syncMacros',
      'syncCns',
      'syncRecovery',
    ]);
    for (final call in calls) {
      expect((call.arguments as Map)['epochDay'], _epochDayOct7);
    }
  });

  test(
    'self-timed and display-ready payloads do not refresh the day stamp',
    () async {
      // MainActivity stamps "synced today" from any call that carries epochDay,
      // so a theme or fasting sync must not claim yesterday's totals are fresh.
      final sync = WidgetSyncService(
        clock: _FixedClock(DateTime(2026, 10, 7, 9)),
      );
      await sync.syncFasting(
        startedAt: null,
        targetSeconds: null,
        planLabel: null,
      );
      await sync.syncTheme(
        mode: ThemeMode.dark,
        dark: HxColors.of(Brightness.dark, AppColorTheme.pinky),
        light: HxColors.of(Brightness.light, AppColorTheme.pinky),
      );
      await sync.syncWidgetData('week', {'done': 2});

      expect(calls, hasLength(3));
      for (final call in calls) {
        expect((call.arguments as Map).containsKey('epochDay'), isFalse);
      }
    },
  );
}
