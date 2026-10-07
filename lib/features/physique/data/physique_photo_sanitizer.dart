import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Face bounding box in pixels of the upright (EXIF-free) image.
class FaceBox {
  const FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Seam over the on-device face detector so tests can fake it.
abstract interface class FaceDetectorPort {
  Future<List<FaceBox>> detect(File uprightImage);
}

class StagedPhoto {
  const StagedPhoto({
    required this.file,
    required this.width,
    required this.height,
    required this.blurRequested,
    required this.facesFound,
    required this.blurApplied,
  });

  final File file;
  final int width;
  final int height;
  final bool blurRequested;
  final int facesFound;
  final bool blurApplied;

  /// Blur was asked for but nothing was blurred because no face was found.
  bool get noFaceFound => blurRequested && facesFound == 0;
}

class PhotoSanitizeException implements Exception {
  PhotoSanitizeException(this.message);

  final String message;

  @override
  String toString() => 'PhotoSanitizeException: $message';
}

const int _storedLongSide = 2048;
const int _analysisLongSide = 1280;

/// Strips all metadata, bakes orientation, caps the long side at 2048 px.
/// Returns (jpeg bytes, width, height). Top-level so it can run in an isolate.
(Uint8List, int, int) sanitizeJpegBytes(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw PhotoSanitizeException('Unsupported or corrupt image');
  }
  var upright = img.bakeOrientation(decoded);
  // bakeOrientation copies every tag except orientation, so GPS would survive.
  upright.exif = img.ExifData();
  upright.iccProfile = null;
  final longSide = math.max(upright.width, upright.height);
  if (longSide > _storedLongSide) {
    upright = upright.width >= upright.height
        ? img.copyResize(
            upright,
            width: _storedLongSide,
            interpolation: img.Interpolation.linear,
          )
        : img.copyResize(
            upright,
            height: _storedLongSide,
            interpolation: img.Interpolation.linear,
          );
    upright.exif = img.ExifData();
    upright.iccProfile = null;
  }
  final bytes = Uint8List.fromList(img.encodeJpg(upright, quality: 88));
  return (bytes, upright.width, upright.height);
}

/// Pixelates each face box (inflated by 25% of its shortest side).
Uint8List pixelateFaceBoxes(Uint8List jpeg, List<FaceBox> boxes) {
  final image = img.decodeJpg(jpeg);
  if (image == null) {
    throw PhotoSanitizeException('Could not decode image for blur');
  }
  for (final box in boxes) {
    final inflate = math.min(box.width, box.height) * 0.25;
    final x0 = (box.left - inflate).floor().clamp(0, image.width - 1);
    final y0 = (box.top - inflate).floor().clamp(0, image.height - 1);
    final x1 = (box.left + box.width + inflate).ceil().clamp(1, image.width);
    final y1 = (box.top + box.height + inflate).ceil().clamp(1, image.height);
    final w = x1 - x0;
    final h = y1 - y0;
    if (w < 2 || h < 2) continue;
    final crop = img.copyCrop(image, x: x0, y: y0, width: w, height: h);
    final blurred = img.pixelate(
      crop,
      size: (w ~/ 6).clamp(8, 64),
      mode: img.PixelateMode.average,
    );
    img.compositeImage(
      image,
      blurred,
      dstX: x0,
      dstY: y0,
      blend: img.BlendMode.direct,
    );
  }
  image.exif = img.ExifData();
  image.iccProfile = null;
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

/// Downscaled, metadata-free copy for the AI backend (<= 1280 px long side).
Uint8List downscaleForAnalysis(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw PhotoSanitizeException('Unsupported or corrupt image');
  }
  var out = img.bakeOrientation(decoded);
  out.exif = img.ExifData();
  out.iccProfile = null;
  if (math.max(out.width, out.height) > _analysisLongSide) {
    out = out.width >= out.height
        ? img.copyResize(
            out,
            width: _analysisLongSide,
            interpolation: img.Interpolation.linear,
          )
        : img.copyResize(
            out,
            height: _analysisLongSide,
            interpolation: img.Interpolation.linear,
          );
    out.exif = img.ExifData();
    out.iccProfile = null;
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

class PhysiquePhotoSanitizer {
  PhysiquePhotoSanitizer({
    required FaceDetectorPort faceDetector,
    Future<Directory> Function()? stagingDirectory,
  }) : _faceDetector = faceDetector,
       _stagingDirectory = stagingDirectory ?? getTemporaryDirectory;

  final FaceDetectorPort _faceDetector;
  final Future<Directory> Function() _stagingDirectory;

  /// Sanitises [source] into a temp file. [source] is never modified.
  Future<StagedPhoto> stage(File source, {bool blurFaces = false}) async {
    final Uint8List input;
    try {
      input = await source.readAsBytes();
    } on FileSystemException catch (e) {
      throw PhotoSanitizeException('Could not read photo: ${e.message}');
    }

    final (Uint8List, int, int) sanitized;
    try {
      sanitized = await Isolate.run(() => sanitizeJpegBytes(input));
    } on PhotoSanitizeException {
      rethrow;
    } on Object catch (e) {
      throw PhotoSanitizeException('Could not process photo: $e');
    }

    final dir = await _stagingDirectory();
    await dir.create(recursive: true);
    final temp = File(
      '${dir.path}${Platform.pathSeparator}physique_${const Uuid().v4()}.jpg',
    );
    try {
      await temp.writeAsBytes(sanitized.$1, flush: true);
      var facesFound = 0;
      var blurApplied = false;
      if (blurFaces) {
        final boxes = await _faceDetector.detect(temp);
        facesFound = boxes.length;
        if (boxes.isNotEmpty) {
          final bytes = sanitized.$1;
          final blurred = await Isolate.run(
            () => pixelateFaceBoxes(bytes, boxes),
          );
          await temp.writeAsBytes(blurred, flush: true);
          blurApplied = true;
        }
      }
      return StagedPhoto(
        file: temp,
        width: sanitized.$2,
        height: sanitized.$3,
        blurRequested: blurFaces,
        facesFound: facesFound,
        blurApplied: blurApplied,
      );
    } on Object catch (e) {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best effort.
      }
      if (e is PhotoSanitizeException) rethrow;
      throw PhotoSanitizeException('Could not process photo: $e');
    }
  }

  Future<Uint8List> analysisBytes(File image) async {
    final input = await image.readAsBytes();
    try {
      return await Isolate.run(() => downscaleForAnalysis(input));
    } on PhotoSanitizeException {
      rethrow;
    } on Object catch (e) {
      throw PhotoSanitizeException('Could not process photo: $e');
    }
  }

  Future<void> discard(StagedPhoto photo) async {
    try {
      if (await photo.file.exists()) await photo.file.delete();
    } on FileSystemException {
      // Tolerant.
    }
  }
}
