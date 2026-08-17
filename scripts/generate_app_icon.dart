// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final logoFile = File('assets/images/logo.png');
  if (!logoFile.existsSync()) {
    print('\n[ERROR] Logo file not found!');
    return;
  }

  print('Reading logo...');
  var logo = img.decodeImage(logoFile.readAsBytesSync());
  if (logo == null) {
    print('Failed to decode logo');
    return;
  }

  print('Cropping to true bounding box to fix off-center issues...');
  int minX = logo.width;
  int minY = logo.height;
  int maxX = 0;
  int maxY = 0;
  
  for (int y = 0; y < logo.height; y++) {
    for (int x = 0; x < logo.width; x++) {
      final pixel = logo.getPixel(x, y);
      if (pixel.a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  
  if (minX <= maxX && minY <= maxY) {
    logo = img.copyCrop(logo, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }

  // Create a 1024x1024 transparent canvas for Android adaptive foreground (4 channels for alpha!)
  final transparentCanvas = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(transparentCanvas, color: img.ColorRgba8(0, 0, 0, 0)); // Ensure it's fully transparent
  
  // Create a 1024x1024 black canvas for iOS and legacy Android
  final blackCanvas = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(blackCanvas, color: img.ColorRgba8(0, 0, 0, 255));

  // We want the logo to take up about 65% of the canvas to ensure it's centered and not clipped by circular masks
  final targetSize = (1024 * 0.65).toInt();
  
  // Calculate scale
  double scale = targetSize / logo.width;
  if (targetSize / logo.height < scale) {
    scale = targetSize / logo.height;
  }
  
  final newWidth = (logo.width * scale).toInt();
  final newHeight = (logo.height * scale).toInt();
  
  print('Resizing and padding...');
  final resizedLogo = img.copyResize(logo, width: newWidth, height: newHeight, interpolation: img.Interpolation.linear);
  
  // Center coordinates
  final dx = (1024 - newWidth) ~/ 2;
  final dy = (1024 - newHeight) ~/ 2;
  
  // Draw onto canvases
  img.compositeImage(transparentCanvas, resizedLogo, dstX: dx, dstY: dy);
  img.compositeImage(blackCanvas, resizedLogo, dstX: dx, dstY: dy);
  
  // Save for flutter_launcher_icons
  File('assets/images/app_icon_foreground.png').writeAsBytesSync(img.encodePng(transparentCanvas));
  File('assets/images/app_icon_ios.png').writeAsBytesSync(img.encodePng(blackCanvas));
  
  print('Generated app icons for Flutter app.');

  // Now let's generate icons for the Watch App directly!
  print('Generating icons for Watch app...');
  final watchResDir = Directory('../Herculex Android Watch/app/src/main/res');
  if (watchResDir.existsSync()) {
    final sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    for (final entry in sizes.entries) {
      final size = entry.value;
      final folder = Directory('${watchResDir.path}/mipmap-${entry.key}');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      
      final resizedForWatch = img.copyResize(blackCanvas, width: size, height: size, interpolation: img.Interpolation.linear);
      File('${folder.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(resizedForWatch));
      File('${folder.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(resizedForWatch));
    }
    print('Successfully applied icons to the Watch app!');
  } else {
    print('Watch app directory not found at ${watchResDir.path}');
  }
}
