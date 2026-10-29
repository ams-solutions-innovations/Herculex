import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';

void main() {
  group('PlatformCapabilities', () {
    test('the test VM reports a native build', () {
      final caps = PlatformCapabilities.current();
      expect(caps.isWeb, isFalse);
      expect(caps.isNative, isTrue);
    });

    test('native builds keep every device capability', () {
      const caps = PlatformCapabilities(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      expect(caps.isAndroid, isTrue);
      expect(caps.hasLocalNotifications, isTrue);
      expect(caps.hasHealthPlatform, isTrue);
      expect(caps.hasHomeWidgets, isTrue);
      expect(caps.hasBundledFoodCatalogue, isTrue);
      expect(caps.hasLiveWorkout, isTrue);
      expect(caps.requiresAccount, isFalse);
      expect(caps.requiresInitialSync, isFalse);
    });

    test('the web has none of them and needs an account', () {
      const caps = PlatformCapabilities.web();
      expect(caps.isNative, isFalse);
      expect(caps.hasLocalNotifications, isFalse);
      expect(caps.hasHealthPlatform, isFalse);
      expect(caps.hasWatchBridge, isFalse);
      expect(caps.hasHomeWidgets, isFalse);
      expect(caps.hasDeviceCalendar, isFalse);
      expect(caps.hasOnDeviceMlKit, isFalse);
      expect(caps.hasFileSystem, isFalse);
      expect(caps.hasBundledFoodCatalogue, isFalse);
      expect(caps.hasLiveWorkout, isFalse);
      expect(caps.requiresAccount, isTrue);
      expect(caps.requiresInitialSync, isTrue);
    });

    test('a browser on Android is not an Android build', () {
      const caps = PlatformCapabilities.web(platform: TargetPlatform.android);
      expect(caps.isAndroid, isFalse);
      expect(caps.isMobileBrowser, isTrue);
    });

    test('the provider can be overridden to exercise web branches', () {
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities.web(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(platformCapabilitiesProvider).isWeb, isTrue);
    });
  });
}
