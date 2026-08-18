// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/images/app_icon_foreground.png');
  final image = img.decodePng(file.readAsBytesSync());
  if (image == null) return;
  print('Channels: ${image.numChannels}');
  
  int transparentCount = 0;
  int opaqueCount = 0;
  
  for (final p in image) {
    if (p.a == 0) {
      transparentCount++;
    } else if (p.a == 255) {
      opaqueCount++;
    }
  }
  print('Transparent pixels: $transparentCount');
  print('Opaque pixels: $opaqueCount');
  print('Total pixels: ${image.width * image.height}');
}
