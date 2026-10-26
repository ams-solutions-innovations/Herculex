import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/storage/local_photo_store.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('hx_local_photo_store_');
    LocalPhotoStore.setDocumentsDirectoryForTesting(docsDir);
  });

  tearDown(() async {
    LocalPhotoStore.setDocumentsDirectoryForTesting(null);
    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  Uint8List makeJpegWithExif() {
    final image = img.Image(width: 24, height: 24);
    img.fill(image, color: img.ColorRgb8(40, 120, 200));
    image.exif.imageIfd['Artist'] = 'Sensitive Author';
    image.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  test('savePickedPhoto strips EXIF/GPS metadata and stores relative sandbox path', () async {
    final sourceFile = File(p.join(docsDir.path, 'picked_raw.jpg'));
    await sourceFile.writeAsBytes(makeJpegWithExif(), flush: true);

    final relativePath = await LocalPhotoStore.savePickedPhoto(
      sourceFile,
      folder: LocalPhotoStore.progressPhotosFolder,
      documentsDirectory: docsDir,
    );

    expect(relativePath, startsWith('progress_photos/'));
    expect(relativePath, endsWith('.jpg'));
    expect(p.isAbsolute(relativePath), isFalse);

    final resolved = LocalPhotoStore.resolveSync(relativePath);
    expect(await resolved.exists(), isTrue);

    final decoded = img.decodeJpg(await resolved.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.exif.imageIfd.isEmpty, isTrue);
    expect(decoded.exif.gpsIfd.isEmpty, isTrue);

    await LocalPhotoStore.deleteStored(relativePath, documentsDirectory: docsDir);
    expect(await resolved.exists(), isFalse);
  });

  test('resolveSync supports both relative sandbox paths and legacy absolute paths', () async {
    final legacyFile = File(p.join(docsDir.path, 'legacy_abs.jpg'));
    await legacyFile.writeAsBytes([1, 2, 3]);

    expect(LocalPhotoStore.resolveSync(legacyFile.path).path, legacyFile.path);
    expect(
      LocalPhotoStore.resolveSync('workout_photos/sample.jpg').path,
      p.join(docsDir.path, 'workout_photos', 'sample.jpg'),
    );
    expect(
      () => LocalPhotoStore.resolveSync('../escape.jpg'),
      throwsArgumentError,
    );
  });

  test('workout_sessions.photo_path is marked local-only in syncTableSpecs', () {
    final spec = syncTableSpecsByName['workout_sessions']!;
    expect(spec.localOnlyColumns, contains('photo_path'));
  });
}
