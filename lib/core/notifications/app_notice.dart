import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';

/// Tone of an [AppNotice].
enum AppNoticeKind { success, info, error }

/// The app's one way to tell the user something happened: the dropping pill
/// at the top of the screen that also announces a new PR.
///
/// Replaces bottom `SnackBar`s and the old centred "squircle" toast, so every
/// confirmation, warning and error looks and behaves the same.
class AppNotice {
  const AppNotice._();

  /// Shows [message] as the pill's headline, with [title] as the small line
  /// above it (defaults by [kind]). [actionLabel] / [onAction] add a button,
  /// e.g. "Undo".
  ///
  /// Works from any context below the root `ProviderScope`. Code that shows
  /// a notice after an `await` should grab [of] first, while the context is
  /// still mounted — the same reason it used to capture `ScaffoldMessenger`.
  static void show(
    BuildContext context,
    String message, {
    String? title,
    AppNoticeKind kind = AppNoticeKind.success,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    of(context).show(
      message,
      title: title,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// A handle that keeps working after [context] is gone.
  static AppNotices of(BuildContext context) =>
      AppNotices._(ProviderScope.containerOf(context, listen: false));

  /// [show] for code that holds a [WidgetRef] rather than a context.
  static void showWith(
    WidgetRef ref,
    String message, {
    String? title,
    AppNoticeKind kind = AppNoticeKind.success,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    ref
        .read(inAppNotificationControllerProvider.notifier)
        .show(
          _item(
            message,
            title: title,
            kind: kind,
            actionLabel: actionLabel,
            onAction: onAction,
            duration: duration,
          ),
        );
  }

  static InAppNotificationItem _item(
    String message, {
    required String? title,
    required AppNoticeKind kind,
    required String? actionLabel,
    required VoidCallback? onAction,
    required Duration? duration,
  }) {
    switch (kind) {
      case AppNoticeKind.success:
        return InAppNotificationItem.success(
          label: title ?? 'Done',
          value: message,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration ?? _durationFor(message, actionLabel),
        );
      case AppNoticeKind.info:
        return InAppNotificationItem.info(
          label: title ?? 'Heads up',
          value: message,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration ?? _durationFor(message, actionLabel),
        );
      case AppNoticeKind.error:
        return InAppNotificationItem.error(
          label: title ?? 'Something went wrong',
          value: message,
          actionLabel: actionLabel,
          onAction: onAction,
          duration:
              duration ??
              _durationFor(message, actionLabel) +
                  const Duration(milliseconds: 1000),
        );
    }
  }

  /// Long enough to read: the pill's entrance plus a hold that grows with
  /// the text, and extra time to reach an action button.
  static Duration _durationFor(String message, String? actionLabel) {
    final readMs = (message.length * 45).clamp(1800, 4500);
    final actionMs = actionLabel == null ? 0 : 1500;
    return Duration(
      milliseconds:
          kAchievementEnterDuration.inMilliseconds + readMs + actionMs,
    );
  }
}

/// See [AppNotice.of].
class AppNotices {
  const AppNotices._(this._container);

  final ProviderContainer _container;

  void show(
    String message, {
    String? title,
    AppNoticeKind kind = AppNoticeKind.success,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    _container
        .read(inAppNotificationControllerProvider.notifier)
        .show(
          AppNotice._item(
            message,
            title: title,
            kind: kind,
            actionLabel: actionLabel,
            onAction: onAction,
            duration: duration,
          ),
        );
  }
}
