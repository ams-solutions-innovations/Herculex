import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_privacy_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late PhysiquePhotoStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('physique_store_');
    store = PhysiquePhotoStore(documentsDirectory: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('relativePathFor has the physique/<goal>/<uuid>.jpg shape', () {
    final p = store.relativePathFor(goalUuid: 'goal-1');
    expect(p, matches(RegExp(r'^physique/goal-1/[0-9a-f-]{36}\.jpg$')));
    expect(
      store.relativePathFor(goalUuid: 'g', fileName: 'a.jpg'),
      'physique/g/a.jpg',
    );
    expect(
      () => store.relativePathFor(goalUuid: ''),
      throwsA(isA<InvalidPhotoPathException>()),
    );
    expect(
      () => store.relativePathFor(goalUuid: 'a/b'),
      throwsA(isA<InvalidPhotoPathException>()),
    );
  });

  test('resolve accepts a legitimate path under the documents dir', () async {
    final f = await store.resolve('physique/g/a.jpg');
    expect(f.path.startsWith(root.path), isTrue);
    expect(f.path.endsWith('a.jpg'), isTrue);
  });

  for (final bad in [
    '../x.jpg',
    '/etc/passwd',
    'physique/../x',
    r'C:\x',
    'other/x.jpg',
    r'physique\x',
    '',
  ]) {
    test('resolve rejects "$bad"', () {
      expect(
        () => store.resolve(bad),
        throwsA(isA<InvalidPhotoPathException>()),
      );
    });
  }

  test('adopt moves the file and leaves no source', () async {
    final src = File('${root.path}/staged.jpg')..writeAsBytesSync([1, 2, 3]);
    final rel = await store.adopt(src, goalUuid: 'g1');
    expect(src.existsSync(), isFalse);
    expect((await store.resolve(rel)).readAsBytesSync(), [1, 2, 3]);
  });

  test('delete on a missing file does not throw', () async {
    await store.delete('physique/g/missing.jpg');
    await store.delete('../bad');
  });

  test('deleteGoalFolder and deleteAll remove folders', () async {
    final a = File('${root.path}/a.jpg')..writeAsBytesSync([1]);
    final b = File('${root.path}/b.jpg')..writeAsBytesSync([2]);
    await store.adopt(a, goalUuid: 'g1');
    await store.adopt(b, goalUuid: 'g2');
    await store.deleteGoalFolder('g1');
    expect(Directory('${root.path}/physique/g1').existsSync(), isFalse);
    expect(Directory('${root.path}/physique/g2').existsSync(), isTrue);
    await store.deleteAll();
    expect(Directory('${root.path}/physique').existsSync(), isFalse);
  });

  group('PhysiquePrivacyPreferences', () {
    test('blur defaults to false and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PhysiquePrivacyPreferences(
        await SharedPreferences.getInstance(),
      );
      expect(prefs.blurFaces, isFalse);
      await prefs.setBlurFaces(true);
      expect(prefs.blurFaces, isTrue);
    });

    test('consent is gated by exact version', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PhysiquePrivacyPreferences(
        await SharedPreferences.getInstance(),
      );
      expect(prefs.hasAcceptedConsent('v1'), isFalse);
      await prefs.acceptConsent('v1');
      expect(prefs.acceptedConsentVersion, 'v1');
      expect(prefs.hasAcceptedConsent('v1'), isTrue);
      expect(prefs.hasAcceptedConsent('v2'), isFalse);
    });
  });
}
