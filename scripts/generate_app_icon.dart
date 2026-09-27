// ignore_for_file: avoid_print

import 'dart:io';

import 'package:image/image.dart' as img;

final _navy = img.ColorRgba8(9, 19, 34, 255);
final _transparent = img.ColorRgba8(0, 0, 0, 0);
final _white = img.ColorRgba8(255, 255, 255, 255);

img.Image _loadMaster() {
  final image = img.decodeImage(
    File('assets/images/app_icon_master.png').readAsBytesSync(),
  );
  if (image == null) {
    throw StateError('Unable to decode assets/images/app_icon_master.png');
  }
  return image;
}

/// Keeps the selected render's exact H/barbell geometry and blue treatment,
/// while removing its navy canvas for Android adaptive icon foregrounds.
img.Image _extractForeground(img.Image master) {
  final result = img.Image(
    width: master.width,
    height: master.height,
    numChannels: 4,
  );
  img.fill(result, color: _transparent);
  for (final pixel in master) {
    // The mark is bright cyan/blue; the navy field remains below this range.
    // The low threshold preserves the anti-aliased outer edge and subtle blue
    // depth from the approved design.
    if (pixel.b > 82 && pixel.g > 52 && pixel.b > pixel.r * 1.8) {
      result.setPixelRgba(pixel.x, pixel.y, pixel.r, pixel.g, pixel.b, 255);
    }
  }
  return result;
}

img.Image _monochrome(img.Image foreground) {
  final result = img.Image(
    width: foreground.width,
    height: foreground.height,
    numChannels: 4,
  );
  img.fill(result, color: _transparent);
  for (final pixel in foreground) {
    if (pixel.a > 0) {
      result.setPixelRgba(pixel.x, pixel.y, _white.r, _white.g, _white.b, pixel.a);
    }
  }
  return result;
}

void _save(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image));
  print('Generated $path');
}

void main() {
  final master = _loadMaster();
  final foreground = _extractForeground(master);
  final monochrome = _monochrome(foreground);

  // The master image is the approved visual, used without redrawing or
  // simplifying it for standard launchers and UI.
  _save('assets/images/logo.png', master);
  _save('assets/images/app_icon_ios.png', master);
  _save('assets/images/app_icon_foreground.png', foreground);
  _save('assets/images/app_icon_monochrome.png', monochrome);
  _save('assets/images/app_icon_ios_dark.png', monochrome);
  _save('assets/images/app_icon_ios_tinted.png', monochrome);

  final watchResDir = Directory('android/wear/src/main/res');
  if (watchResDir.existsSync()) {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in sizes.entries) {
      final mipmap = Directory('${watchResDir.path}/mipmap-${entry.key}')
        ..createSync(recursive: true);
      final drawable = Directory('${watchResDir.path}/drawable-${entry.key}')
        ..createSync(recursive: true);
      final standardResized = img.copyResize(
        master,
        width: entry.value,
        height: entry.value,
      );
      _save('${mipmap.path}/ic_launcher.png', standardResized);
      _save('${mipmap.path}/ic_launcher_round.png', standardResized);
      _save(
        '${drawable.path}/ic_launcher_foreground.png',
        img.copyResize(foreground, width: entry.value, height: entry.value),
      );
      _save(
        '${drawable.path}/ic_launcher_monochrome.png',
        img.copyResize(monochrome, width: entry.value, height: entry.value),
      );
    }
  }
}
