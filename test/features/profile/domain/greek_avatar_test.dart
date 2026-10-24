import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  group('GreekAvatar catalog', () {
    test('contains all 13 Greek gods, demigods, titans, and legends', () {
      expect(GreekAvatars.all.length, 13);
      final ids = GreekAvatars.all.map((a) => a.id).toSet();
      expect(ids.length, 13);
      expect(
        ids,
        containsAll([
          'hercules',
          'zeus',
          'poseidon',
          'ares',
          'athena',
          'apollo',
          'hades',
          'hermes',
          'artemis',
          'achilles',
          'perseus',
          'atlas',
          'prometheus',
        ]),
      );
    });

    test(
      'findById resolves valid avatar IDs case-insensitively and returns null for unknown',
      () {
        expect(GreekAvatars.findById('hercules')?.name, 'Hercules');
        expect(GreekAvatars.findById('  ATHENA ')?.name, 'Athena');
        expect(
          GreekAvatars.findById('atlas')?.category,
          GreekAvatarCategory.titans,
        );
        expect(
          GreekAvatars.findById('achilles')?.category,
          GreekAvatarCategory.legends,
        );
        expect(GreekAvatars.findById(null), isNull);
        expect(GreekAvatars.findById(''), isNull);
        expect(GreekAvatars.findById('unknown_god'), isNull);
      },
    );

    test('byCategory filters avatars accurately', () {
      expect(GreekAvatars.byCategory(null).length, GreekAvatars.all.length);
      final olympians = GreekAvatars.byCategory(GreekAvatarCategory.gods);
      expect(
        olympians.map((a) => a.id),
        containsAll([
          'zeus',
          'poseidon',
          'ares',
          'athena',
          'apollo',
          'hades',
          'hermes',
          'artemis',
        ]),
      );

      final demigods = GreekAvatars.byCategory(GreekAvatarCategory.demigods);
      expect(demigods.map((a) => a.id), containsAll(['hercules', 'perseus']));

      final titans = GreekAvatars.byCategory(GreekAvatarCategory.titans);
      expect(titans.map((a) => a.id), containsAll(['atlas', 'prometheus']));

      final legends = GreekAvatars.byCategory(GreekAvatarCategory.legends);
      expect(legends.map((a) => a.id), contains('achilles'));
    });
  });

  group('Profile avatarId serialization', () {
    test('persists and clears avatarId via toJson / fromJson / copyWith', () {
      const profile = Profile(
        name: 'Martin',
        avatarId: 'hercules',
        weightKg: 82.0,
        activityLevel: ActivityLevel.active,
        goal: FitnessGoal.maintenance,
      );
      final json = profile.toJson();
      expect(json['avatarId'], 'hercules');

      final restored = Profile.fromJson(json);
      expect(restored.avatarId, 'hercules');
      expect(restored.name, 'Martin');

      final updated = restored.copyWith(avatarId: 'zeus');
      expect(updated.avatarId, 'zeus');

      final cleared = updated.copyWith(clearAvatarId: true);
      expect(cleared.avatarId, isNull);
    });
  });
}
