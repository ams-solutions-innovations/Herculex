import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Builds a gradient JPEG carrying make/model/orientation/GPS EXIF.
Uint8List buildJpegWithExif({
  int width = 64,
  int height = 48,
  bool withGps = true,
  int orientation = 6,
}) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = (p.x * 255 / width).round()
      ..g = (p.y * 255 / height).round()
      ..b = ((p.x + p.y) * 255 / (width + height)).round();
  }
  image.exif.imageIfd.make = 'TestMake';
  image.exif.imageIfd.model = 'TestModel';
  image.exif.imageIfd.orientation = orientation;
  if (withGps) {
    image.exif.gpsIfd.gpsLatitude = 46.05;
    image.exif.gpsIfd.gpsLongitude = 14.5;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}
