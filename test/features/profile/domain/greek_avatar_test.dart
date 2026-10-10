import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  group('GreekAvatar', () {
    test('contains all 13 mythological figures', () {
      expect(GreekAvatar.all.length, 13);
      final ids = GreekAvatar.all.map((a) => a.id).toSet();
      expect(ids.length, 13, reason: 'All avatar IDs must be unique');

      expect(
        ids,
        containsAll([
          'zeus',
          'poseidon',
          'ares',
          'athena',
          'apollo',
          'hades',
          'hermes',
          'artemis',
          'hercules',
          'perseus',
          'atlas',
          'prometheus',
          'achilles',
        ]),
      );
    });

    test('covers all four categories: gods, demigods, titans, legends', () {
      final gods = GreekAvatar.all.where(
        (a) => a.category == GreekAvatarCategory.gods,
      );
      final demigods = GreekAvatar.all.where(
        (a) => a.category == GreekAvatarCategory.demigods,
      );
      final titans = GreekAvatar.all.where(
        (a) => a.category == GreekAvatarCategory.titans,
      );
      final legends = GreekAvatar.all.where(
        (a) => a.category == GreekAvatarCategory.legends,
      );

      expect(gods.length, 8);
      expect(demigods.length, 2);
      expect(titans.length, 2);
      expect(legends.length, 1);
    });

    test('every avatar has non-empty fields and Greek name', () {
      for (final a in GreekAvatar.all) {
        expect(a.id, isNotEmpty);
        expect(a.name, isNotEmpty);
        expect(a.greekName, isNotEmpty);
        expect(a.title, isNotEmpty);
        expect(a.lore, isNotEmpty);
        expect(a.assetPath, startsWith('assets/images/avatars/'));
        expect(a.primaryColor.value, isNonZero);
      }
    });

    test('findById returns matching avatar or null', () {
      expect(GreekAvatar.findById('hercules')?.name, 'Hercules');
      expect(GreekAvatar.findById('zeus')?.name, 'Zeus');
      expect(GreekAvatar.findById('atlas')?.name, 'Atlas');
      expect(GreekAvatar.findById('achilles')?.name, 'Achilles');
      expect(GreekAvatar.findById(null), isNull);
      expect(GreekAvatar.findById(''), isNull);
      expect(GreekAvatar.findById('unknown_character'), isNull);
    });

    test('every declared avatar asset file exists on disk', () {
      for (final a in GreekAvatar.all) {
        final file = File(a.assetPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Asset file ${a.assetPath} must exist on disk',
        );
      }
    });
  });

  group('Profile with avatarId', () {
    test(
      'supports avatarId in constructor, copyWith, toJson, and fromJson',
      () {
        const initial = Profile(
          name: 'Leonidas',
          avatarId: 'hercules',
          goal: FitnessGoal.muscleGain,
          activityLevel: ActivityLevel.veryActive,
        );

        expect(initial.avatarId, 'hercules');

        // Test copyWith updating avatarId
        final updated = initial.copyWith(avatarId: 'zeus');
        expect(updated.avatarId, 'zeus');
        expect(updated.name, 'Leonidas');

        // Test copyWith clearing avatarId
        final cleared = updated.copyWith(clearAvatarId: true);
        expect(cleared.avatarId, isNull);

        // Test JSON roundtrip
        final json = updated.toJson();
        expect(json['avatarId'], 'zeus');

        final reconstructed = Profile.fromJson(json);
        expect(reconstructed.avatarId, 'zeus');
        expect(reconstructed.name, 'Leonidas');

        // Test backwards compatibility with snake_case avatar_id
        final legacyJson = {
          'name': 'Spartan',
          'avatar_id': 'atlas',
          'goal': 'maintenance',
          'activityLevel': 'active',
        };
        final fromLegacy = Profile.fromJson(legacyJson);
        expect(fromLegacy.avatarId, 'atlas');
        expect(fromLegacy.name, 'Spartan');
      },
    );
  });
}
