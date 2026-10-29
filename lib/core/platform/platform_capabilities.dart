import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the platform the app runs on can do.
///
/// Every web/native difference goes through here instead of `Platform.isX`
/// (which throws on the web) or a bare `kIsWeb`, so the web branches can be
/// exercised on the VM by overriding [platformCapabilitiesProvider].
///
/// Native-only capabilities are `!isWeb` rather than "Android or iOS": the web
/// track must not change what any native build does.
@immutable
class PlatformCapabilities {
  const PlatformCapabilities({required this.isWeb, required this.platform});

  /// The platform this build is running on.
  factory PlatformCapabilities.current() =>
      PlatformCapabilities(isWeb: kIsWeb, platform: defaultTargetPlatform);

  /// A browser. [platform] is the OS the browser runs on.
  const PlatformCapabilities.web({this.platform = TargetPlatform.windows})
    : isWeb = true;

  final bool isWeb;
  final TargetPlatform platform;

  bool get isNative => !isWeb;
  bool get isAndroid => isNative && platform == TargetPlatform.android;
  bool get isIOS => isNative && platform == TargetPlatform.iOS;

  /// A browser on a phone or tablet — wide-screen layout rules don't apply
  /// just because it is the web.
  bool get isMobileBrowser =>
      isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

  bool get hasLocalNotifications => isNative;
  bool get hasHealthPlatform => isNative;
  bool get hasWatchBridge => isNative;
  bool get hasHomeWidgets => isNative;
  bool get hasWorkoutBubble => isNative;

  /// Starting and logging a workout set by set is done at the gym, on the
  /// phone. The web plans and reviews training (templates, programs, history)
  /// but offers no way to begin a session.
  bool get hasLiveWorkout => isNative;
  bool get hasAppShortcuts => isNative;
  bool get hasDeviceCalendar => isNative;
  bool get hasMediaControls => isNative;

  /// ML Kit text recognition / face detection. On the web, label scanning
  /// goes straight to Gemini and face blur is unavailable.
  bool get hasOnDeviceMlKit => isNative;

  /// A writable app sandbox (path_provider, `dart:io` files). Photo files
  /// never sync, so on the web they simply don't exist.
  bool get hasFileSystem => isNative;

  /// The 49 MB EU food database ships in the native bundle only; the web
  /// searches the `food_catalogue` table instead.
  bool get hasBundledFoodCatalogue => isNative;

  /// Phones work fully offline without an account; the web has no local-only
  /// mode — every session belongs to a signed-in user.
  bool get requiresAccount => isWeb;

  /// A fresh browser database starts empty, so the first cloud pull has to
  /// finish before anything writes defaults that would duplicate pulled rows.
  bool get requiresInitialSync => isWeb;

  @override
  bool operator ==(Object other) =>
      other is PlatformCapabilities &&
      other.isWeb == isWeb &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(isWeb, platform);

  @override
  String toString() =>
      'PlatformCapabilities(${isWeb ? 'web' : 'native'}, ${platform.name})';
}

final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (_) => PlatformCapabilities.current(),
);
