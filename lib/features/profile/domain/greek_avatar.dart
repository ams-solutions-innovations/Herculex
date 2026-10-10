import 'package:flutter/material.dart';

/// Categories of Greek mythological profile avatars.
enum GreekAvatarCategory {
  gods('Bogovi', 'Olympian Gods'),
  demigods('Demi-bogovi', 'Demigods'),
  titans('Titani', 'Titans'),
  legends('Legende', 'Legends');

  final String label;
  final String englishLabel;

  const GreekAvatarCategory(this.label, this.englishLabel);
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
    // ── Bogovi (Gods) ──────────────────────────────────────────────────────────
    GreekAvatar(
      id: 'zeus',
      name: 'Zeus',
      greekName: 'Ζεύς',
      category: GreekAvatarCategory.gods,
      title: 'Kralj Olimpa in gospodar strele',
      lore: 'Vladar Olimpa. Tvoja disciplina in moč premikata meje mogočega.',
      assetPath: 'assets/images/avatars/zeus.jpg',
      primaryColor: Color(0xFF64D2FF),
    ),
    GreekAvatar(
      id: 'poseidon',
      name: 'Poseidon',
      greekName: 'Ποσειδῶν',
      category: GreekAvatarCategory.gods,
      title: 'Gospodar morij in viharjev',
      lore: 'Neukrotljiva sila oceanov. Val za valom premagaj vsako oviro.',
      assetPath: 'assets/images/avatars/poseidon.jpg',
      primaryColor: Color(0xFF00B4D8),
    ),
    GreekAvatar(
      id: 'ares',
      name: 'Ares',
      greekName: 'Ἄρης',
      category: GreekAvatarCategory.gods,
      title: 'Bog vojne in neustrašnosti',
      lore:
          'Brezkompromisni bojevnik. V vsaki seriji se bori do konca brez obžalovanja.',
      assetPath: 'assets/images/avatars/ares.jpg',
      primaryColor: Color(0xFFFF453A),
    ),
    GreekAvatar(
      id: 'athena',
      name: 'Athena',
      greekName: 'Ἀθηνᾶ',
      category: GreekAvatarCategory.gods,
      title: 'Boginja modrosti in strategije',
      lore:
          'Umetnost inteligentnega treninga. Znanje, tehnika in nepremagljiva volja.',
      assetPath: 'assets/images/avatars/athena.jpg',
      primaryColor: Color(0xFFFFD166),
    ),
    GreekAvatar(
      id: 'apollo',
      name: 'Apollo',
      greekName: 'Ἀπόλλων',
      category: GreekAvatarCategory.gods,
      title: 'Bog sonca, svetlobe in harmonije',
      lore:
          'Sijaj v svoji popolni telesni formi. Natančnost, moč in ravnovesje.',
      assetPath: 'assets/images/avatars/apollo.jpg',
      primaryColor: Color(0xFFFFD60A),
    ),
    GreekAvatar(
      id: 'hades',
      name: 'Hades',
      greekName: 'ᾍδης',
      category: GreekAvatarCategory.gods,
      title: 'Gospodar podzemlja in skritih moči',
      lore:
          'Resnična moč se kali v tišini in nevidnem trudu globoko pod površjem.',
      assetPath: 'assets/images/avatars/hades.jpg',
      primaryColor: Color(0xFFBF5AF2),
    ),
    GreekAvatar(
      id: 'hermes',
      name: 'Hermes',
      greekName: 'Ἑρμῆς',
      category: GreekAvatarCategory.gods,
      title: 'Glasnik bogov, hitrost in agilnost',
      lore:
          'Eksplozivna hitrost in lahkotnost gibanja. Zmaga je v hitri regeneraciji.',
      assetPath: 'assets/images/avatars/hermes.jpg',
      primaryColor: Color(0xFF30D158),
    ),
    GreekAvatar(
      id: 'artemis',
      name: 'Artemis',
      greekName: 'Ἄρτεμις',
      category: GreekAvatarCategory.gods,
      title: 'Boginja lova in neukročene narave',
      lore:
          'Brezhiben fokus na vsak cilj. Vzdržljivost v naravnem ritmu telesa.',
      assetPath: 'assets/images/avatars/artemis.jpg',
      primaryColor: Color(0xFF52B788),
    ),

    // ── Demi-bogovi (Demigods) ────────────────────────────────────────────────
    GreekAvatar(
      id: 'hercules',
      name: 'Hercules',
      greekName: 'Ἡρακλῆς',
      category: GreekAvatarCategory.demigods,
      title: 'Polbog neprekosljive moči',
      lore:
          'Zaščitnik Herculexa. Premagal je 12 nalog z nečloveško močjo in železnim značajem.',
      assetPath: 'assets/images/avatars/hercules.jpg',
      primaryColor: Color(0xFF0A84FF),
    ),
    GreekAvatar(
      id: 'perseus',
      name: 'Perseus',
      greekName: 'Περσεύς',
      category: GreekAvatarCategory.demigods,
      title: 'Zmagovalec mitoloških pošasti',
      lore:
          'Pogum pred največjimi izzivi. Zmaga pripada tistim, ki nikoli ne odnehajo.',
      assetPath: 'assets/images/avatars/perseus.jpg',
      primaryColor: Color(0xFF4DA3FF),
    ),

    // ── Titani (Titans) ───────────────────────────────────────────────────────
    GreekAvatar(
      id: 'atlas',
      name: 'Atlas',
      greekName: 'Ἄτλας',
      category: GreekAvatarCategory.titans,
      title: 'Titan nebeškega svoda in teže',
      lore:
          'Nosi cel svet na svojih ramenih. Za tvoj hrbet in ramena nobena utež ni pretežka.',
      assetPath: 'assets/images/avatars/atlas.jpg',
      primaryColor: Color(0xFFE0A96D),
    ),
    GreekAvatar(
      id: 'prometheus',
      name: 'Prometheus',
      greekName: 'Προμηθεύς',
      category: GreekAvatarCategory.titans,
      title: 'Titan večnega ognja in upora',
      lore:
          'Prižgi notranji plamen strasti in discipline, ki ga nič ne more ugasniti.',
      assetPath: 'assets/images/avatars/prometheus.jpg',
      primaryColor: Color(0xFFFF9F0A),
    ),

    // ── Legende (Legends) ─────────────────────────────────────────────────────
    GreekAvatar(
      id: 'achilles',
      name: 'Achilles',
      greekName: 'Ἀχιλλεύς',
      category: GreekAvatarCategory.legends,
      title: 'Največji bojevnik antike',
      lore:
          'Legenda nesmrtne slave. Vsak trening je priložnost za zapis med večne prvake.',
      assetPath: 'assets/images/avatars/achilles.jpg',
      primaryColor: Color(0xFFD4AF37),
    ),
  ];

  static GreekAvatar? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final avatar in all) {
      if (avatar.id == id) return avatar;
    }
    return null;
  }
}
