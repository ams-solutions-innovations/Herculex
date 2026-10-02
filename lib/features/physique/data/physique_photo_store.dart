import 'dart:io';

import 'package:uuid/uuid.dart';

/// Thrown when a relative photo path could escape the physique sandbox.
class InvalidPhotoPathException implements Exception {
  InvalidPhotoPathException(this.path);

  final String path;

  @override
  String toString() => 'InvalidPhotoPathException: $path';
}

/// Sandbox for private physique photos under the app documents directory.
///
/// Photos are addressed by relative paths (`physique/<goalUuid>/<uuid>.jpg`).
/// This class is the only code that turns such a path into a [File].
class PhysiquePhotoStore {
  PhysiquePhotoStore({required Future<Directory> Function() documentsDirectory})
    : _documentsDirectory = documentsDirectory;

  static const String rootFolderName = 'physique';

  final Future<Directory> Function() _documentsDirectory;

  String _checkGoalUuid(String goalUuid) {
    if (goalUuid.isEmpty ||
        goalUuid.contains('/') ||
        goalUuid.contains(r'\') ||
        goalUuid.contains('..') ||
        goalUuid.contains(':')) {
      throw InvalidPhotoPathException(goalUuid);
    }
    return goalUuid;
  }

  String relativePathFor({required String goalUuid, String? fileName}) {
    _checkGoalUuid(goalUuid);
    final name = fileName ?? '${const Uuid().v4()}.jpg';
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      throw InvalidPhotoPathException(name);
    }
    return '$rootFolderName/$goalUuid/$name';
  }

  Future<File> resolve(String relativePath) async {
    if (relativePath.isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relativePath)) {
      throw InvalidPhotoPathException(relativePath);
    }
    final segments = relativePath.split('/');
    if (segments.any((s) => s.isEmpty || s == '..' || s == '.') ||
        segments.first != rootFolderName ||
        segments.length < 2) {
      throw InvalidPhotoPathException(relativePath);
    }
    final root = await _documentsDirectory();
    return File(
      '${root.path}${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}',
    );
  }

  /// Moves [staged] into `physique/<goalUuid>/` and returns the relative path.
  Future<String> adopt(File staged, {required String goalUuid}) async {
    final relative = relativePathFor(goalUuid: goalUuid);
    final target = await resolve(relative);
    await target.parent.create(recursive: true);
    try {
      await staged.rename(target.path);
    } on FileSystemException {
      await staged.copy(target.path);
      try {
        await staged.delete();
      } on FileSystemException {
        // Best effort: the sanitised copy already lives in the sandbox.
      }
    }
    return relative;
  }

  Future<void> delete(String relativePath) async {
    try {
      final file = await resolve(relativePath);
      if (await file.exists()) await file.delete();
    } on Object {
      // Tolerant by design: a missing or locked file must not block cleanup.
    }
  }

  Future<void> deleteGoalFolder(String goalUuid) async {
    try {
      _checkGoalUuid(goalUuid);
      final root = await _documentsDirectory();
      final dir = Directory(
        '${root.path}${Platform.pathSeparator}$rootFolderName'
        '${Platform.pathSeparator}$goalUuid',
      );
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Tolerant, see [delete].
    }
  }

  Future<void> deleteAll() async {
    try {
      final root = await _documentsDirectory();
      final dir = Directory(
        '${root.path}${Platform.pathSeparator}$rootFolderName',
      );
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Tolerant, see [delete].
    }
  }
}
