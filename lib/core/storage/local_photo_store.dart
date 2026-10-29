import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Sandboxed local storage for progress photos and workout finish photos.
///
/// Picked images are stripped of all EXIF/GPS/ICC metadata in a background
/// isolate, rotated upright, encoded as clean JPEG, and stored under
/// `<Documents>/progress_photos/<uuid>.jpg` or
/// `<Documents>/workout_photos/<uuid>.jpg`.
///
/// Only the relative POSIX path (`progress_photos/<uuid>.jpg`) is persisted in
/// SQLite so paths remain portable across iOS container UUID rotations while
/// legacy absolute paths continue to resolve transparently via [resolveSync].
class LocalPhotoStore {
  LocalPhotoStore._();

  static const String progressPhotosFolder = 'progress_photos';
  static const String workoutPhotosFolder = 'workout_photos';

  static const MethodChannel _privacyChannel = MethodChannel(
    'com.ams.herculex/storage_privacy',
  );

  static Directory? _cachedDocumentsDirectory;

  /// Initializes the cached Documents directory at app startup so widget
  /// `build()` methods can resolve relative photo paths synchronously.
  static Future<Directory?> initialize({Directory? override}) async {
    if (override != null) {
      _cachedDocumentsDirectory = override;
      return override;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      _cachedDocumentsDirectory = dir;
      await excludeFromBackup();
      return dir;
    } catch (_) {
      return _cachedDocumentsDirectory;
    }
  }

  /// Sets or clears the cached Documents directory in unit/widget tests.
  static void setDocumentsDirectoryForTesting(Directory? directory) {
    _cachedDocumentsDirectory = directory;
  }

  /// Synchronously resolves [storedPath] (either a new sandbox-relative POSIX
  /// path such as `progress_photos/<uuid>.jpg` or a legacy absolute path) to a
  /// [File].
  static File resolveSync(String storedPath, {Directory? documentsDirectory}) {
    final trimmed = storedPath.trim();
    final docs = documentsDirectory ?? _cachedDocumentsDirectory;
    if (trimmed.isEmpty || p.isAbsolute(trimmed) || docs == null) {
      return File(trimmed);
    }
    final segments = trimmed.split(RegExp(r'[/\\]'));
    if (segments.any((s) => s == '..')) {
      throw ArgumentError.value(
        storedPath,
        'storedPath',
        'Relative photo path must not traverse parent directories',
      );
    }
    return File(p.joinAll([docs.path, ...segments.where((s) => s.isNotEmpty)]));
  }

  /// Asynchronously resolves [storedPath], ensuring the Documents directory has
  /// been discovered if [initialize] has not run yet.
  static Future<File> resolve(
    String storedPath, {
    Directory? documentsDirectory,
  }) async {
    final docs =
        documentsDirectory ?? _cachedDocumentsDirectory ?? await initialize();
    return resolveSync(storedPath, documentsDirectory: docs);
  }

  /// Sanitizes [source] (stripping EXIF/GPS/ICC metadata and baking upright
  /// orientation), writes it into `<Documents>/<folder>/<uuid>.jpg`, and
  /// returns its relative POSIX path (`<folder>/<uuid>.jpg`).
  static Future<String> savePickedPhoto(
    File source, {
    required String folder,
    Directory? documentsDirectory,
  }) async {
    if (folder != progressPhotosFolder && folder != workoutPhotosFolder) {
      throw ArgumentError.value(folder, 'folder', 'Unsupported photo folder');
    }
    final docs =
        documentsDirectory ??
        _cachedDocumentsDirectory ??
        await getApplicationDocumentsDirectory();
    _cachedDocumentsDirectory ??= docs;

    final rawBytes = await source.readAsBytes();
    final (sanitizedBytes, _, _) = await compute(sanitizeJpegBytes, rawBytes);

    final fileName = '${const Uuid().v4()}.jpg';
    final targetDir = Directory(p.join(docs.path, folder));
    await targetDir.create(recursive: true);
    final targetFile = File(p.join(targetDir.path, fileName));
    await targetFile.writeAsBytes(sanitizedBytes, flush: true);

    // Best-effort cleanup of ImagePicker temporary cache copy if it lives in
    // the OS temporary directory so unstripped EXIF copies do not linger.
    try {
      final tempDir = await getTemporaryDirectory();
      if (p.isWithin(tempDir.path, source.path) &&
          source.path != targetFile.path &&
          await source.exists()) {
        await source.delete();
      }
    } catch (_) {}

    await excludeFromBackup();
    return '$folder/$fileName';
  }

  /// Deletes a stored photo file if [storedPath] is a sandbox-relative path or
  /// resides inside the app's Documents/Temporary container.
  static Future<void> deleteStored(
    String? storedPath, {
    Directory? documentsDirectory,
  }) async {
    if (storedPath == null || storedPath.trim().isEmpty) return;
    final trimmed = storedPath.trim();
    try {
      final docs =
          documentsDirectory ?? _cachedDocumentsDirectory ?? await initialize();
      final isRelative = !p.isAbsolute(trimmed);
      final resolved = resolveSync(trimmed, documentsDirectory: docs);
      var safeToDelete = isRelative;
      if (!safeToDelete && docs != null) {
        safeToDelete = p.isWithin(docs.path, resolved.path);
      }
      if (!safeToDelete) {
        try {
          final tempDir = await getTemporaryDirectory();
          safeToDelete = p.isWithin(tempDir.path, resolved.path);
        } catch (_) {}
      }
      if (!safeToDelete) {
        safeToDelete = p.isWithin(Directory.systemTemp.path, resolved.path);
      }
      if (safeToDelete && await resolved.exists()) {
        await resolved.delete();
      }
    } catch (_) {
      // Tolerant cleanup: missing/locked files must not block DB updates.
    }
  }

  /// Asks iOS to mark SQLite database files and private photo folders with
  /// `NSURLIsExcludedFromBackupKey = true`. Safe no-op on Android and in tests.
  static Future<void> excludeFromBackup() async {
    if (!PlatformCapabilities.current().isIOS) return;
    try {
      await _privacyChannel.invokeMethod<void>('excludeFromBackup');
    } on PlatformException {
      // Non-fatal.
    } on MissingPluginException {
      // Headless tests.
    } catch (_) {}
  }
}
