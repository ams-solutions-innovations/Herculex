import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/app.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/error/app_error_handler.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/core/storage/local_photo_store.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/data/sync/preferences/syncing_shared_preferences.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/auth/data/secure_auth_storage.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First thing after the binding: everything below — timezone lookup, the
  // Supabase handshake — can throw, and until these hooks are installed a
  // throw there is an unreported black screen.
  AppErrorHandler.install();

  tz.initializeTimeZones();
  // Without this, tz.local defaults to UTC, so every zonedSchedule call
  // (fasting goal/schedule notifications, live workout timers) fires at the
  // wrong wall-clock time for any device outside UTC. Best-effort: an
  // unresolvable identifier leaves tz.local at UTC rather than crashing
  // startup.
  try {
    final deviceTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(deviceTz.identifier));
  } catch (_) {}

  final caps = PlatformCapabilities.current();
  if (caps.isWeb) {
    // Real paths (`/insights`, not `/#/insights`), and pushed screens show in
    // the address bar so a reload or a shared link lands on the same screen.
    usePathUrlStrategy();
    GoRouter.optionURLReflectsImperativeAPIs = true;
  } else {
    WearSyncService.initialize();
    await LocalPhotoStore.initialize();

    // The widget channel carries inbound deep links (`openActiveWorkout`,
    // `openScanner`, ...) but its handler is only registered once
    // `_HerculexAppState.initState` runs, so on a cold start — the normal case
    // when opening from the Workout Bubble or a home-screen widget — the link
    // arrives first. Flutter's default per-channel buffer holds a single message
    // and warns on overflow, so a second event during the same startup would
    // discard the first. Same idiom `WearSyncService.initialize` uses.
    ServicesBinding.instance.channelBuffers.resize(
      'com.ams.herculex/widget',
      16,
    );
  }

  // Guarded so tests and credential-less dev builds still run — the app is
  // local-first and stays fully usable without a backend.
  if (Env.hasSupabase) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // The keychain/keystore on phones; on the web supabase_flutter's
        // default (window.localStorage) — there is no secure storage there.
        localStorage: caps.isWeb ? null : SecureAuthStorage(),
      ),
    );
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Wrapped so the profile and settings can follow the account to other
  // devices (see app/synced_preferences.dart); behaves exactly like the
  // plain instance otherwise.
  final prefs = SyncingSharedPreferences(await SharedPreferences.getInstance());

  // Resolve the palette brightness and color theme before the first frame.
  // Reading the saved mode (and the platform brightness for `system`) here is what
  // stops the app flashing wrong surfaces on startup.
  final savedMode = prefs.getString('theme_mode') ?? 'system';
  final effectiveBrightness = switch (savedMode) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => PlatformDispatcher.instance.platformBrightness,
  };
  AppColors.brightness = effectiveBrightness;

  final savedColorTheme = prefs.getString('app_color_theme') ?? 'classicBlue';
  final effectiveColorTheme = AppColorTheme.values.firstWhere(
    (t) => t.name == savedColorTheme,
    orElse: () => AppColorTheme.classicBlue,
  );
  AppColors.colorTheme = effectiveColorTheme;

  final isDark = effectiveBrightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const HerculexApp(),
    ),
  );
}
