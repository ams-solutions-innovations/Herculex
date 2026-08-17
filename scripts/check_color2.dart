// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/images/app_icon_foreground.png');
  final image = img.decodePng(file.readAsBytesSync());
  if (image == null) return;
  
  for (final p in image) {
    if (p.a == 255) {
      print('Found opaque pixel: R=${p.r}, G=${p.g}, B=${p.b}, A=${p.a}');
      break;
    }
  }
}
