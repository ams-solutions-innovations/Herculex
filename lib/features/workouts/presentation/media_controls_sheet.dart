import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_media_controller/flutter_media_controller.dart';

import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';

/// Premium media controls bottom sheet.
///
/// Reads the currently playing track from any media app (Spotify, YouTube
/// Music, etc.) via Android's NotificationListenerService and lets the user
/// control playback without leaving the workout screen.
///
/// Usage:
/// ```dart
/// MediaControlsSheet.show(context);
/// ```
class MediaControlsSheet extends StatefulWidget {
  const MediaControlsSheet({super.key});

  /// Convenience method — shows the sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => const MediaControlsSheet(),
    );
  }

  @override
  State<MediaControlsSheet> createState() => _MediaControlsSheetState();
}

class _MediaControlsSheetState extends State<MediaControlsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  Timer? _refreshTimer;

  String _track = '';
  String _artist = '';
  bool _isPlaying = false;
  Uint8List? _thumbnail;

  /// True once we have tried at least one media fetch.
  bool _loaded = false;

  /// True when the native result indicates permission hasn't been granted.
  bool _needsPermission = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _refresh();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final info = await FlutterMediaController.getCurrentMediaInfo();
      if (!mounted) return;

      // The native side returns "No track playing" when no Notification Listener
      // permission is granted or when nothing is actually playing.
      final noPermission = info.track == 'No track playing' && !info.isPlaying;

      // thumbnailUrl is a base64-encoded PNG from the Android side.
      Uint8List? thumb;
      if (info.thumbnailUrl.isNotEmpty) {
        try {
          thumb = base64Decode(info.thumbnailUrl);
        } catch (_) {
          thumb = null;
        }
      }

      setState(() {
        _needsPermission = noPermission;
        _track = noPermission ? '' : info.track;
        _artist = noPermission ? '' : info.artist;
        _isPlaying = info.isPlaying;
        _thumbnail = thumb;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _needsPermission = true;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    // Opens Android's Notification Listener Settings page.
    await FlutterMediaController.requestPermissions();
    // Re-poll after a short delay to pick up the grant.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceContainer,
            AppColors.surfaceContainerLowest,
          ],
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ────────────────────────────────────
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Header ─────────────────────────────────────────
              Row(
                children: [
                  ScaleTransition(
                    scale: _isPlaying
                        ? _pulseAnim
                        : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Media Controls',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Content ────────────────────────────────────────
              if (!_loaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else if (_needsPermission)
                _PermissionPrompt(onRequest: _requestPermission)
              else
                _MediaContent(
                  track: _track,
                  artist: _artist,
                  isPlaying: _isPlaying,
                  thumbnail: _thumbnail,
                  onPlayPause: () async {
                    Haptics.medium();
                    await FlutterMediaController.togglePlayPause();
                    await _refresh();
                  },
                  onNext: () async {
                    Haptics.light();
                    await FlutterMediaController.nextTrack();
                    await Future<void>.delayed(
                        const Duration(milliseconds: 400));
                    await _refresh();
                  },
                  onPrevious: () async {
                    Haptics.light();
                    await FlutterMediaController.previousTrack();
                    await Future<void>.delayed(
                        const Duration(milliseconds: 400));
                    await _refresh();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Media Content
// ─────────────────────────────────────────────────────────────────────────────

class _MediaContent extends StatelessWidget {
  final String track;
  final String artist;
  final bool isPlaying;
  final Uint8List? thumbnail;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const _MediaContent({
    required this.track,
    required this.artist,
    required this.isPlaying,
    required this.thumbnail,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Album art ─────────────────────────────────────────
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.surfaceVariant,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: thumbnail != null
              ? Image.memory(
                  thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _AlbumArtPlaceholder(),
                )
              : _AlbumArtPlaceholder(),
        ),

        const SizedBox(height: 20),

        // ── Track info ────────────────────────────────────────
        Text(
          track.isNotEmpty ? track : 'Nothing playing',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.secondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // ── Controls ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(
              icon: Icons.skip_previous_rounded,
              size: 36,
              onTap: onPrevious,
            ),
            const SizedBox(width: 24),
            _PlayPauseButton(
              isPlaying: isPlaying,
              onTap: onPlayPause,
            ),
            const SizedBox(width: 24),
            _ControlButton(
              icon: Icons.skip_next_rounded,
              size: 36,
              onTap: onNext,
            ),
          ],
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: Icon(
        Icons.music_note_rounded,
        size: 56,
        color: AppColors.outlineVariant,
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _scaleCtrl.reverse();
    widget.onTap();
    await _scaleCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: child,
            ),
            child: Icon(
              widget.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              key: ValueKey(widget.isPlaying),
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          size: size,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission prompt
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Notification Access Required',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Herculex needs Notification Access to read the\n'
            'currently playing track from Spotify and other apps.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Open Settings'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
