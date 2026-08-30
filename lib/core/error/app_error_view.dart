import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// The widget Flutter renders in place of a subtree whose `build` threw.
///
/// Hard constraint: this replaces an *arbitrary* widget at an *arbitrary*
/// point in the tree, so it can land inside a `Row`, a `ListView`, or above
/// `MaterialApp` entirely. It therefore must not
///
/// * look anything up from `Theme`/`MediaQuery`/`Directionality` — none are
///   guaranteed to exist above it (this is why it reads the static
///   [AppColors] rather than `context.hx`),
/// * assume it has bounded or unbounded constraints in either axis, or
/// * throw. An exception here would recurse straight back into
///   `ErrorWidget.builder`.
///
/// It is intentionally non-interactive: a retry button needs a `Navigator`
/// that may not be above it. Recovery actions live in [AppErrorScreen], which
/// is used for the router's `errorBuilder` where a real context does exist.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Release builds show a neutral line instead of the exception text —
    // exception messages routinely carry ids and file paths.
    final text = kReleaseMode ? 'Something went wrong here.' : message;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: kReleaseMode ? 2 : 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppColors.onSurfaceVariant,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen error surface, used where a real `Navigator` exists — the
/// `GoRouter` `errorBuilder` for unmatched or malformed routes.
class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({super.key, required this.message, this.onGoHome});

  final String message;
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    final text = kReleaseMode
        ? "That screen couldn't be opened."
        : message;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (onGoHome != null)
                    FilledButton(
                      onPressed: onGoHome,
                      child: const Text('Go home'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
