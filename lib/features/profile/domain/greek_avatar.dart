import 'package:flutter/material.dart';

/// Categories of Greek mythological profile avatars.
enum GreekAvatarCategory {
  gods('Olympian Gods', Icons.bolt_rounded),
  demigods('Demigods', Icons.shield_rounded),
  titans('Titans', Icons.public_rounded),
  legends('Legends', Icons.military_tech_rounded);

  final String label;
  final IconData icon;

  const GreekAvatarCategory(this.label, this.icon);
}

/// Representation of a selectable mythological avatar.
class GreekAvatar {
  final String id;
  final String name;
  final String greekName;
  final GreekAvatarCategory category;
  final String title;
  final String lore;
  final String assetPath;
  final Color primaryColor;

  Color get accentColor => primaryColor;

  const GreekAvatar({
    required this.id,
    required this.name,
    required this.greekName,
    required this.category,
    required this.title,
    required this.lore,
    required this.assetPath,
    required this.primaryColor,
  });

  /// Full roster of available avatars fitting the Herculex UI.
  static const List<GreekAvatar> all = [
    // ── Olympian Gods ──────────────────────────────────────────────────────────
    GreekAvatar(
      id: 'zeus',
      name: 'Zeus',
      greekName: 'Ζεύς',
      category: GreekAvatarCategory.gods,
      title: 'King of Olympus & God of Thunder',
      lore:
          'Ruler of the heavens. Your discipline and power push beyond every limit.',
      assetPath: 'assets/images/avatars/zeus.jpg',
      primaryColor: Color(0xFF64D2FF),
    ),
    GreekAvatar(
      id: 'poseidon',
      name: 'Poseidon',
      greekName: 'Ποσειδῶν',
      category: GreekAvatarCategory.gods,
      title: 'Lord of the Seas & Tempests',
      lore:
          'Unstoppable force of the oceans. Wave after wave, crush every obstacle.',
      assetPath: 'assets/images/avatars/poseidon.jpg',
      primaryColor: Color(0xFF00B4D8),
    ),
    GreekAvatar(
      id: 'ares',
      name: 'Ares',
      greekName: 'Ἄρης',
      category: GreekAvatarCategory.gods,
      title: 'God of War & Fearless Valor',
      lore:
          'Relentless warrior. Fight through every set until the very last rep.',
      assetPath: 'assets/images/avatars/ares.jpg',
      primaryColor: Color(0xFFFF453A),
    ),
    GreekAvatar(
      id: 'athena',
      name: 'Athena',
      greekName: 'Ἀθηνᾶ',
      category: GreekAvatarCategory.gods,
      title: 'Goddess of Wisdom & Strategy',
      lore:
          'The art of intelligent training. Precision, form, and unbreakable will.',
      assetPath: 'assets/images/avatars/athena.jpg',
      primaryColor: Color(0xFFFFD166),
    ),
    GreekAvatar(
      id: 'apollo',
      name: 'Apollo',
      greekName: 'Ἀπόλλων',
      category: GreekAvatarCategory.gods,
      title: 'God of the Sun, Light & Harmony',
      lore:
          'Radiate peak physical and mental form. Focus, balance, and perfection.',
      assetPath: 'assets/images/avatars/apollo.jpg',
      primaryColor: Color(0xFFFFD60A),
    ),
    GreekAvatar(
      id: 'hades',
      name: 'Hades',
      greekName: 'ᾍδης',
      category: GreekAvatarCategory.gods,
      title: 'Lord of the Underworld & Hidden Power',
      lore:
          'True strength is forged in silence and unseen effort deep beneath the surface.',
      assetPath: 'assets/images/avatars/hades.jpg',
      primaryColor: Color(0xFFBF5AF2),
    ),
    GreekAvatar(
      id: 'hermes',
      name: 'Hermes',
      greekName: 'Ἑρμῆς',
      category: GreekAvatarCategory.gods,
      title: 'Herald of the Gods, Speed & Agility',
      lore:
          'Explosive speed and effortless motion. Victory favors swift recovery.',
      assetPath: 'assets/images/avatars/hermes.jpg',
      primaryColor: Color(0xFF30D158),
    ),
    GreekAvatar(
      id: 'artemis',
      name: 'Artemis',
      greekName: 'Ἄρτεμις',
      category: GreekAvatarCategory.gods,
      title: 'Goddess of the Hunt & Untamed Nature',
      lore:
          'Unwavering focus on every target. Endurance in the natural rhythm of the body.',
      assetPath: 'assets/images/avatars/artemis.jpg',
      primaryColor: Color(0xFF52B788),
    ),

    // ── Demigods ───────────────────────────────────────────────────────────────
    GreekAvatar(
      id: 'hercules',
      name: 'Hercules',
      greekName: 'Ἡρακλῆς',
      category: GreekAvatarCategory.demigods,
      title: 'Demigod of Unrivaled Strength',
      lore:
          'Patron of Herculex. Conquered the Twelve Labors through sheer power and iron resolve.',
      assetPath: 'assets/images/avatars/hercules.jpg',
      primaryColor: Color(0xFF0A84FF),
    ),
    GreekAvatar(
      id: 'perseus',
      name: 'Perseus',
      greekName: 'Περσεύς',
      category: GreekAvatarCategory.demigods,
      title: 'Slayer of Mythic Monsters',
      lore:
          'Courage against impossible odds. Victory belongs to those who never back down.',
      assetPath: 'assets/images/avatars/perseus.jpg',
      primaryColor: Color(0xFF4DA3FF),
    ),

    // ── Titans ─────────────────────────────────────────────────────────────────
    GreekAvatar(
      id: 'atlas',
      name: 'Atlas',
      greekName: 'Ἄτλας',
      category: GreekAvatarCategory.titans,
      title: 'Titan of the Celestial Sphere & Endurance',
      lore:
          'Carries the heavens upon his shoulders. No weight is too heavy for an unbreakable back.',
      assetPath: 'assets/images/avatars/atlas.jpg',
      primaryColor: Color(0xFFE0A96D),
    ),
    GreekAvatar(
      id: 'prometheus',
      name: 'Prometheus',
      greekName: 'Προμηθεύς',
      category: GreekAvatarCategory.titans,
      title: 'Titan of Eternal Fire & Defiance',
      lore:
          'Ignite the inner flame of passion and discipline that nothing can extinguish.',
      assetPath: 'assets/images/avatars/prometheus.jpg',
      primaryColor: Color(0xFFFF9F0A),
    ),

    // ── Legends ────────────────────────────────────────────────────────────────
    GreekAvatar(
      id: 'achilles',
      name: 'Achilles',
      greekName: 'Ἀχιλλεύς',
      category: GreekAvatarCategory.legends,
      title: 'Greatest Warrior of Antiquity',
      lore:
          'Legend of immortal glory. Every workout is a chance to etch your name among champions.',
      assetPath: 'assets/images/avatars/achilles.jpg',
      primaryColor: Color(0xFFD4AF37),
    ),
  ];

  static GreekAvatar? findById(String? id) {
    final normalized = id?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final avatar in all) {
      if (avatar.id == normalized) return avatar;
    }
    return null;
  }

  static List<GreekAvatar> byCategory(GreekAvatarCategory? category) {
    if (category == null) return all;
    return all.where((a) => a.category == category).toList(growable: false);
  }
}

/// Static lookup helper for [GreekAvatar] portraits.
abstract final class GreekAvatars {
  static const List<GreekAvatar> all = GreekAvatar.all;

  static GreekAvatar? findById(String? id) => GreekAvatar.findById(id);

  static List<GreekAvatar> byCategory(GreekAvatarCategory? category) =>
      GreekAvatar.byCategory(category);
}
