import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show PlatformDispatcher;

import 'app/app.dart';
import 'app/providers.dart';
import 'theme/colors.dart';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'core/env.dart';
import 'features/auth/data/secure_auth_storage.dart';
import 'features/nutrition/data/wear_sync_service.dart';
import 'features/reps/data/rep_profile_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  WearSyncService.initialize();

  // Assisted rep tracking reads its per-exercise capability profiles from an
  // asset into an in-memory registry, so this has to run on every launch —
  // unlike the exercise catalogue, which is imported into the database on
  // install and migration only. Until it completes, every exercise reports as
  // unsupported and no tracking surfaces anywhere; the load is best-effort and
  // never blocks startup on failure.
  await RepProfileLoader.load();

  // Guarded so tests and credential-less dev builds still run — the app is
  // local-first and stays fully usable without a backend.
  if (Env.hasSupabase) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureAuthStorage(),
      ),
    );
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();

  // Resolve the palette brightness before the first frame. Reading the saved
  // mode (and the platform brightness for `system`) here is what stops the
  // app flashing dark surfaces on a light device during startup.
  final savedMode = prefs.getString('theme_mode') ?? 'system';
  final effectiveBrightness = switch (savedMode) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => PlatformDispatcher.instance.platformBrightness,
  };
  AppColors.brightness = effectiveBrightness;

  final isDark = effectiveBrightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  ));

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const HerculexApp(),
    ),
  );
}