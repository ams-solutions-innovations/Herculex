import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the top-dropping in-app notification pill is coloured.
enum NotificationStyle {
  /// Always the dark pill.
  dark('Dark'),

  /// Always the light pill.
  light('Light'),

  /// Follows the app: light/dark mode and the accent theme (pinky, yellow...).
  app('App theme');

  const NotificationStyle(this.label);
  final String label;
}

/// Resolved colours for one pill.
class NotificationPalette {
  const NotificationPalette({
    required this.surface,
    required this.border,
    required this.shadow,
    required this.label,
    required this.value,
    required this.onBadge,
  });

  final Color surface;
  final Color border;
  final Color shadow;
  final Color label;
  final Color value;

  /// Icon colour inside the filled circular badge.
  final Color onBadge;

  static const dark = NotificationPalette(
    surface: Color(0xFF161E2E),
    border: Color(0xFF2B374E),
    shadow: Color.fromRGBO(4, 9, 19, 0.55),
    label: Color(0xFF94A3B8),
    value: Colors.white,
    onBadge: Color(0xFF091322),
  );

  static const light = NotificationPalette(
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFD9DFEA),
    shadow: Color.fromRGBO(30, 41, 59, 0.18),
    label: Color(0xFF64748B),
    value: Color(0xFF0F172A),
    onBadge: Color(0xFF091322),
  );

  /// Built from the app's own palette so the pill carries the accent theme in
  /// both light and dark mode.
  factory NotificationPalette.fromApp(HxColors hx) {
    final isDark = hx.brightness == Brightness.dark;
    return NotificationPalette(
      surface: Color.alphaBlend(
        hx.primary.withValues(alpha: isDark ? 0.14 : 0.10),
        hx.surfaceContainer,
      ),
      border: hx.primary.withValues(alpha: 0.35),
      shadow: Color.fromRGBO(0, 0, 0, isDark ? 0.5 : 0.16),
      label: hx.onSurfaceVariant,
      value: hx.onSurface,
      onBadge: const Color(0xFF091322),
    );
  }

  static NotificationPalette resolve(NotificationStyle style, HxColors hx) =>
      switch (style) {
        NotificationStyle.dark => dark,
        NotificationStyle.light => light,
        NotificationStyle.app => NotificationPalette.fromApp(hx),
      };
}

const _kPrefKey = 'notification_style';

final notificationStyleProvider =
    StateNotifierProvider<NotificationStyleNotifier, NotificationStyle>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // Not wired (widget tests that mount the host alone): use the default.
      }
      final saved = prefs?.getString(_kPrefKey);
      final initial = NotificationStyle.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => NotificationStyle.app,
      );
      return NotificationStyleNotifier(initial, prefs);
    });

class NotificationStyleNotifier extends StateNotifier<NotificationStyle> {
  NotificationStyleNotifier(super.initial, this._prefs);
  final SharedPreferences? _prefs;

  void set(NotificationStyle style) {
    state = style;
    _prefs?.setString(_kPrefKey, style.name);
  }
}
