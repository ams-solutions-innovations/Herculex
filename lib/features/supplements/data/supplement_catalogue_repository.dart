import 'dart:convert';

import 'package:herculex/core/utils/env.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/product_catalogue_repository.dart';
import 'package:herculex/features/nutrition/data/remote_food.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Categories in the built-in supplement database.
const supplementCatalogueCategories = <String>[
  'All',
  'Performance',
  'Vitamins',
  'Minerals',
  'Omega & Health',
  'Protein & Amino',
  'Recovery & Sleep',
];

class SupplementCatalogueEntry {
  final String id;
  final String name;
  final String? brand;
  final String category;
  final String? barcode;
  final double? doseAmount;
  final String? doseUnit;
  final Map<String, double> nutrients;
  final SupplementSchedule schedule;
  final String? timeHHMM;
  final String? description;

  const SupplementCatalogueEntry({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    this.barcode,
    this.doseAmount,
    this.doseUnit,
    this.nutrients = const {},
    this.schedule = SupplementSchedule.none,
    this.timeHHMM,
    this.description,
  });

  Supplement toSupplement({String? overrideId, String? overrideBarcode}) {
    return Supplement(
      id: overrideId ?? const Uuid().v4(),
      name: name,
      brand: brand,
      barcode: overrideBarcode ?? barcode,
      doseAmount: doseAmount,
      doseUnit: doseUnit,
      nutrients: nutrients,
      schedule: schedule,
      timeHHMM: schedule == SupplementSchedule.time ? timeHHMM : null,
    );
  }
}

class SupplementLookupResult {
  final Supplement supplement;
  final String sourceLabel;

  const SupplementLookupResult({
    required this.supplement,
    required this.sourceLabel,
  });
}

/// Curated built-in database of common supplements, brands, doses, and
/// micronutrient contributions.
const kBuiltInSupplementCatalogue = <SupplementCatalogueEntry>[
  // ── Performance ──────────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_creatine_mono',
    name: 'Creatine Monohydrate',
    category: 'Performance',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
    description: 'Daily 5 g dose for strength, power, and muscle saturation.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_on_creatine',
    name: 'Micronized Creatine Powder',
    brand: 'Optimum Nutrition',
    category: 'Performance',
    barcode: '0748927023879',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
    description: '100% pure micronized creatine monohydrate (5 g per scoop).',
  ),
  SupplementCatalogueEntry(
    id: 'cat_myprotein_creatine',
    name: 'Creatine Monohydrate',
    brand: 'Myprotein',
    category: 'Performance',
    barcode: '5055534301876',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
  ),
  SupplementCatalogueEntry(
    id: 'cat_gymbeam_creatine',
    name: '100% Creatine Monohydrate',
    brand: 'GymBeam',
    category: 'Performance',
    barcode: '8588006139174',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
  ),
  SupplementCatalogueEntry(
    id: 'cat_esn_creatine',
    name: 'Ultrapure Creatine Monohydrate',
    brand: 'ESN',
    category: 'Performance',
    barcode: '4250519603844',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
  ),
  SupplementCatalogueEntry(
    id: 'cat_caffeine_200',
    name: 'Caffeine Anhydrous',
    category: 'Performance',
    doseAmount: 200,
    doseUnit: 'mg',
    nutrients: {'caffeine': 200},
    schedule: SupplementSchedule.none,
    description: 'Pre-workout alertness and ergogenic support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_pre_workout',
    name: 'Pre-Workout Formula',
    category: 'Performance',
    doseAmount: 1,
    doseUnit: 'scoop',
    nutrients: {'caffeine': 200, 'vitamin_b12': 5, 'sodium': 100},
    schedule: SupplementSchedule.none,
    description: 'Standard pre-workout scoop with caffeine, citrulline & B12.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_beta_alanine',
    name: 'Beta-Alanine',
    category: 'Performance',
    doseAmount: 3.2,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
    description: 'Supports muscular endurance and carnosine buffering.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_citrulline_malate',
    name: 'L-Citrulline Malate 2:1',
    category: 'Performance',
    doseAmount: 6,
    doseUnit: 'g',
    schedule: SupplementSchedule.none,
    description: 'Nitric oxide support and blood flow before training.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_electrolytes',
    name: 'Electrolytes & Hydration',
    category: 'Performance',
    doseAmount: 1,
    doseUnit: 'scoop',
    nutrients: {
      'sodium': 500,
      'potassium': 300,
      'magnesium': 60,
      'calcium': 40,
    },
    schedule: SupplementSchedule.postWorkout,
    description: 'Replenishes key sweat electrolytes after training.',
  ),

  // ── Vitamins ─────────────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_vit_d3_1000',
    name: 'Vitamin D3 (1000 IU)',
    category: 'Vitamins',
    doseAmount: 25,
    doseUnit: 'µg',
    nutrients: {'vitamin_d': 25},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Daily maintenance Vitamin D3 (25 µg = 1000 IU).',
  ),
  SupplementCatalogueEntry(
    id: 'cat_vit_d3_4000',
    name: 'Vitamin D3 (4000 IU)',
    category: 'Vitamins',
    doseAmount: 100,
    doseUnit: 'µg',
    nutrients: {'vitamin_d': 100},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'High-strength Vitamin D3 (100 µg = 4000 IU).',
  ),
  SupplementCatalogueEntry(
    id: 'cat_vit_d3_k2',
    name: 'Vitamin D3 + K2 MK-7',
    category: 'Vitamins',
    doseAmount: 1,
    doseUnit: 'capsule',
    nutrients: {'vitamin_d': 50, 'vitamin_k': 100},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Synergistic bone, immune, and cardiovascular support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_vit_c_1000',
    name: 'Vitamin C 1000 mg',
    category: 'Vitamins',
    doseAmount: 1000,
    doseUnit: 'mg',
    nutrients: {'vitamin_c': 1000},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Antioxidant and immune support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_vit_b12',
    name: 'Vitamin B12 Methylcobalamin',
    category: 'Vitamins',
    doseAmount: 500,
    doseUnit: 'µg',
    nutrients: {'vitamin_b12': 500},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Energy metabolism and nervous system support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_b_complex',
    name: 'Vitamin B-Complex',
    category: 'Vitamins',
    doseAmount: 1,
    doseUnit: 'capsule',
    nutrients: {'vitamin_b12': 25, 'folate': 400},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Full-spectrum B vitamins with folate and B12.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_multivitamin',
    name: 'Daily Multivitamin & Minerals',
    category: 'Vitamins',
    doseAmount: 1,
    doseUnit: 'capsule',
    nutrients: {
      'vitamin_a': 800,
      'vitamin_c': 80,
      'vitamin_d': 15,
      'vitamin_e': 12,
      'vitamin_k': 75,
      'vitamin_b12': 2.5,
      'folate': 200,
      'iron': 10,
      'magnesium': 100,
      'zinc': 10,
      'calcium': 160,
    },
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Comprehensive once-daily micronutrient coverage.',
  ),

  // ── Minerals ─────────────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_magnesium_bisglycinate',
    name: 'Magnesium Bisglycinate',
    category: 'Minerals',
    doseAmount: 400,
    doseUnit: 'mg',
    nutrients: {'magnesium': 400},
    schedule: SupplementSchedule.time,
    timeHHMM: '21:00',
    description: 'Highly bioavailable chelated magnesium for sleep & recovery.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_magnesium_citrate',
    name: 'Magnesium Citrate',
    category: 'Minerals',
    doseAmount: 300,
    doseUnit: 'mg',
    nutrients: {'magnesium': 300},
    schedule: SupplementSchedule.time,
    timeHHMM: '20:30',
  ),
  SupplementCatalogueEntry(
    id: 'cat_zinc_picolinate',
    name: 'Zinc Picolinate',
    category: 'Minerals',
    doseAmount: 15,
    doseUnit: 'mg',
    nutrients: {'zinc': 15},
    schedule: SupplementSchedule.time,
    timeHHMM: '20:00',
    description: 'Immune function, hormone support, and recovery.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_zma',
    name: 'ZMA (Zinc + Magnesium + B6)',
    category: 'Minerals',
    doseAmount: 2,
    doseUnit: 'capsule',
    nutrients: {'magnesium': 450, 'zinc': 30},
    schedule: SupplementSchedule.time,
    timeHHMM: '21:30',
    description: 'Nighttime mineral recovery complex.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_iron_bisglycinate',
    name: 'Iron Bisglycinate + Vitamin C',
    category: 'Minerals',
    doseAmount: 1,
    doseUnit: 'capsule',
    nutrients: {'iron': 18, 'vitamin_c': 60, 'folate': 200},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Gentle chelated iron paired with Vitamin C for absorption.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_calcium_citrate',
    name: 'Calcium + Vitamin D3',
    category: 'Minerals',
    doseAmount: 500,
    doseUnit: 'mg',
    nutrients: {'calcium': 500, 'vitamin_d': 15},
    schedule: SupplementSchedule.time,
    timeHHMM: '12:00',
  ),
  SupplementCatalogueEntry(
    id: 'cat_potassium_citrate',
    name: 'Potassium Citrate',
    category: 'Minerals',
    doseAmount: 300,
    doseUnit: 'mg',
    nutrients: {'potassium': 300},
    schedule: SupplementSchedule.time,
    timeHHMM: '12:00',
  ),

  // ── Omega & Health ───────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_omega3_fish_oil',
    name: 'Omega-3 Fish Oil (EPA & DHA)',
    category: 'Omega & Health',
    doseAmount: 2,
    doseUnit: 'capsule',
    nutrients: {'omega_3': 2.0, 'vitamin_e': 5},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: '2 softgels providing 2 g of Omega-3 fatty acids (EPA/DHA).',
  ),
  SupplementCatalogueEntry(
    id: 'cat_algae_omega3',
    name: 'Vegan Algae Omega-3',
    category: 'Omega & Health',
    doseAmount: 1,
    doseUnit: 'capsule',
    nutrients: {'omega_3': 1.0},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
  ),
  SupplementCatalogueEntry(
    id: 'cat_coq10',
    name: 'Coenzyme Q10 (Ubiquinol)',
    category: 'Omega & Health',
    doseAmount: 100,
    doseUnit: 'mg',
    schedule: SupplementSchedule.time,
    timeHHMM: '08:30',
    description: 'Mitochondrial energy and cardiovascular antioxidant.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_probiotics',
    name: 'Probiotics Multi-Strain',
    category: 'Omega & Health',
    doseAmount: 1,
    doseUnit: 'capsule',
    schedule: SupplementSchedule.time,
    timeHHMM: '07:30',
    description: 'Gut microbiome and digestive support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_psyllium_husk',
    name: 'Psyllium Husk Fiber',
    category: 'Omega & Health',
    doseAmount: 5,
    doseUnit: 'g',
    nutrients: {'fiber': 4.5},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
  ),

  // ── Protein & Amino ──────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_whey_protein',
    name: 'Whey Protein Isolate / Concentrate',
    category: 'Protein & Amino',
    doseAmount: 30,
    doseUnit: 'g',
    nutrients: {'calcium': 120, 'potassium': 150, 'sodium': 60},
    schedule: SupplementSchedule.postWorkout,
    description: '1 scoop (30 g) post-workout protein shake.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_on_gold_whey',
    name: 'Gold Standard 100% Whey',
    brand: 'Optimum Nutrition',
    category: 'Protein & Amino',
    barcode: '0748927028669',
    doseAmount: 30,
    doseUnit: 'g',
    nutrients: {'calcium': 130, 'potassium': 160, 'sodium': 50},
    schedule: SupplementSchedule.postWorkout,
  ),
  SupplementCatalogueEntry(
    id: 'cat_collagen_peptides',
    name: 'Hydrolyzed Collagen Peptides',
    category: 'Protein & Amino',
    doseAmount: 10,
    doseUnit: 'g',
    nutrients: {'vitamin_c': 50},
    schedule: SupplementSchedule.time,
    timeHHMM: '08:00',
    description: 'Joint, tendon, ligament, and skin connective tissue support.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_eaa_bcaa',
    name: 'Essential Amino Acids (EAA)',
    category: 'Protein & Amino',
    doseAmount: 10,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
  ),
  SupplementCatalogueEntry(
    id: 'cat_l_glutamine',
    name: 'L-Glutamine',
    category: 'Protein & Amino',
    doseAmount: 5,
    doseUnit: 'g',
    schedule: SupplementSchedule.postWorkout,
  ),

  // ── Recovery & Sleep ─────────────────────────────────────────────────────
  SupplementCatalogueEntry(
    id: 'cat_ashwagandha',
    name: 'Ashwagandha KSM-66',
    category: 'Recovery & Sleep',
    doseAmount: 600,
    doseUnit: 'mg',
    schedule: SupplementSchedule.time,
    timeHHMM: '21:00',
    description: 'Adaptogen for cortisol management, stress, and recovery.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_l_theanine',
    name: 'L-Theanine',
    category: 'Recovery & Sleep',
    doseAmount: 200,
    doseUnit: 'mg',
    schedule: SupplementSchedule.time,
    timeHHMM: '21:00',
    description: 'Promotes calm focus and evening relaxation.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_melatonin',
    name: 'Melatonin',
    category: 'Recovery & Sleep',
    doseAmount: 1,
    doseUnit: 'mg',
    schedule: SupplementSchedule.time,
    timeHHMM: '22:00',
    description: 'Supports sleep onset and circadian rhythm alignment.',
  ),
  SupplementCatalogueEntry(
    id: 'cat_glycine',
    name: 'L-Glycine',
    category: 'Recovery & Sleep',
    doseAmount: 3,
    doseUnit: 'g',
    schedule: SupplementSchedule.time,
    timeHHMM: '21:30',
    description: 'Supports deep sleep quality and collagen synthesis.',
  ),
];

/// Unified supplement database combining:
/// 1. The user's active supplements & locally saved supplement catalogue
/// 2. The built-in curated supplement database ([kBuiltInSupplementCatalogue])
/// 3. The local Drift `foods` table (`category = 'supplement'` or barcode hit)
/// 4. The shared Supabase `product_catalogue`
/// 5. OpenFoodFacts fallback
class SupplementCatalogueRepository {
  static const _localCatalogueKey = 'supplements_catalogue_v1';

  final SharedPreferences _prefs;
  final SupplementRepository _supplementRepo;
  final dynamic Function()? _nutritionGetter;
  final ProductCatalogueRepository Function()? _productCatalogueGetter;
  final OpenFoodFactsClient Function()? _openFoodFactsGetter;

  const SupplementCatalogueRepository({
    required SharedPreferences prefs,
    required SupplementRepository supplementRepo,
    dynamic Function()? nutritionGetter,
    ProductCatalogueRepository Function()? productCatalogueGetter,
    OpenFoodFactsClient Function()? openFoodFactsGetter,
  }) : _prefs = prefs,
       _supplementRepo = supplementRepo,
       _nutritionGetter = nutritionGetter,
       _productCatalogueGetter = productCatalogueGetter,
       _openFoodFactsGetter = openFoodFactsGetter;

  /// Loads custom/scanned supplements saved into the local catalogue.
  List<Supplement> loadLocalCatalogue() {
    final raw = _prefs.getString(_localCatalogueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return Supplement.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  /// Saves or updates a supplement in the local supplement database so future
  /// searches and barcode scans find it immediately.
  Future<void> saveToLocalCatalogue(Supplement supplement) async {
    final current = loadLocalCatalogue();
    final normalizedCode = supplement.barcode == null
        ? null
        : (normalizeBarcode(supplement.barcode!)?.value ??
              supplement.barcode!.trim());
    final updatedItem = normalizedCode != null
        ? supplement.copyWith(barcode: normalizedCode)
        : supplement;

    final filtered = current.where((s) {
      if (normalizedCode != null &&
          normalizedCode.isNotEmpty &&
          s.barcode != null) {
        final sCode = normalizeBarcode(s.barcode!)?.value ?? s.barcode!.trim();
        if (sCode == normalizedCode) return false;
      }
      return !(s.name.toLowerCase() == updatedItem.name.toLowerCase() &&
          (s.brand ?? '').toLowerCase() ==
              (updatedItem.brand ?? '').toLowerCase());
    }).toList();

    filtered.insert(0, updatedItem);
    await _prefs.setString(_localCatalogueKey, Supplement.listToJson(filtered));
  }

  /// Searches the supplement database (user saved + built-in catalogue) by
  /// [query] and optional [category].
  List<SupplementCatalogueEntry> search(
    String query, {
    String category = 'All',
  }) {
    final q = query.trim().toLowerCase();
    final results = <SupplementCatalogueEntry>[];
    final seenKeys = <String>{};

    // 1. User's saved local catalogue entries + active supplements
    if (category == 'All') {
      final localItems = [
        ...loadLocalCatalogue(),
        ..._supplementRepo.loadSupplements(),
      ];
      for (final s in localItems) {
        final key = '${s.name.toLowerCase()}|${(s.brand ?? '').toLowerCase()}';
        if (seenKeys.contains(key)) continue;
        final matchesQuery =
            q.isEmpty ||
            s.name.toLowerCase().contains(q) ||
            (s.brand?.toLowerCase().contains(q) ?? false) ||
            (s.barcode?.toLowerCase().contains(q) ?? false);
        if (!matchesQuery) continue;
        seenKeys.add(key);
        results.add(
          SupplementCatalogueEntry(
            id: 'local_${s.id}',
            name: s.name,
            brand: s.brand,
            category: 'Saved',
            barcode: s.barcode,
            doseAmount: s.doseAmount,
            doseUnit: s.doseUnit,
            nutrients: s.nutrients,
            schedule: s.schedule,
            timeHHMM: s.timeHHMM,
            description: 'Saved in your supplement database',
          ),
        );
      }
    }

    // 2. Built-in curated supplement database
    for (final entry in kBuiltInSupplementCatalogue) {
      if (category != 'All' && entry.category != category) continue;
      final key =
          '${entry.name.toLowerCase()}|${(entry.brand ?? '').toLowerCase()}';
      if (seenKeys.contains(key)) continue;
      final matchesQuery =
          q.isEmpty ||
          entry.name.toLowerCase().contains(q) ||
          (entry.brand?.toLowerCase().contains(q) ?? false) ||
          entry.category.toLowerCase().contains(q) ||
          (entry.description?.toLowerCase().contains(q) ?? false) ||
          (entry.barcode?.toLowerCase().contains(q) ?? false);
      if (!matchesQuery) continue;
      seenKeys.add(key);
      results.add(entry);
    }

    return results;
  }

  /// Looks up a supplement barcode across all database layers before falling
  /// back to AI analysis:
  /// 1. User's active supplements & local supplement catalogue
  /// 2. Built-in curated supplement catalogue
  /// 3. Local Drift `foods` table
  /// 4. Shared Supabase `product_catalogue`
  /// 5. OpenFoodFacts API
  Future<SupplementLookupResult?> lookupByBarcode(String rawBarcode) async {
    final trimmed = rawBarcode.trim();
    if (trimmed.isEmpty) return null;

    final normalized = normalizeBarcode(trimmed);
    final candidates = <String>{
      trimmed,
      if (normalized != null) ...normalized.lookupCandidates,
    };

    // 1. Active supplements & local supplement catalogue
    final localItems = [
      ..._supplementRepo.loadSupplements(),
      ...loadLocalCatalogue(),
    ];
    for (final s in localItems) {
      if (s.barcode == null || s.barcode!.isEmpty) continue;
      final sNorm = normalizeBarcode(s.barcode!);
      final sCandidates = <String>{
        s.barcode!.trim(),
        if (sNorm != null) ...sNorm.lookupCandidates,
      };
      if (sCandidates.intersection(candidates).isNotEmpty) {
        return SupplementLookupResult(
          supplement: s.copyWith(barcode: normalized?.value ?? trimmed),
          sourceLabel: 'My Supplement DB',
        );
      }
    }

    // 2. Built-in curated supplement catalogue
    for (final entry in kBuiltInSupplementCatalogue) {
      if (entry.barcode == null || entry.barcode!.isEmpty) continue;
      final eNorm = normalizeBarcode(entry.barcode!);
      final eCandidates = <String>{
        entry.barcode!.trim(),
        if (eNorm != null) ...eNorm.lookupCandidates,
      };
      if (eCandidates.intersection(candidates).isNotEmpty) {
        return SupplementLookupResult(
          supplement: entry.toSupplement(
            overrideBarcode: normalized?.value ?? trimmed,
          ),
          sourceLabel: 'Herculex Supplement DB',
        );
      }
    }

    // 3. Local Drift foods database
    try {
      final nutritionRepo = _nutritionGetter?.call();
      if (nutritionRepo != null) {
        final FoodData? food = await nutritionRepo.lookupBarcode(trimmed);
        if (food != null) {
          final supp = _supplementFromFoodData(
            food,
            normalized?.value ?? trimmed,
          );
          return SupplementLookupResult(
            supplement: supp,
            sourceLabel: 'Local Product DB',
          );
        }
      }
    } catch (_) {
      // Ignore DB lookup errors and continue to remote catalogues
    }

    // 4. Shared Supabase community product_catalogue
    if (Env.hasSupabase) {
      try {
        final catalogRepo = _productCatalogueGetter?.call();
        if (catalogRepo != null) {
          for (final code in candidates) {
            final publicProduct = await catalogRepo.lookupByBarcode(code);
            if (publicProduct != null) {
              final supp = _supplementFromPublicProduct(
                publicProduct,
                normalized?.value ?? trimmed,
              );
              await saveToLocalCatalogue(supp);
              return SupplementLookupResult(
                supplement: supp,
                sourceLabel: 'Herculex Community DB',
              );
            }
          }
        }
      } catch (_) {
        // Non-fatal
      }
    }

    // 5. OpenFoodFacts fallback
    try {
      final offClient = _openFoodFactsGetter?.call();
      if (offClient != null) {
        final RemoteFood? remote = await offClient.lookupBarcode(
          normalized?.value ?? trimmed,
        );
        if (remote != null) {
          final supp = _supplementFromRemoteFood(
            remote,
            normalized?.value ?? trimmed,
          );
          await saveToLocalCatalogue(supp);
          return SupplementLookupResult(
            supplement: supp,
            sourceLabel: 'OpenFoodFacts DB',
          );
        }
      }
    } catch (_) {
      // Non-fatal
    }

    return null;
  }

  Supplement _supplementFromFoodData(FoodData food, String barcode) {
    final nutrients = <String, double>{};
    SupplementSchedule schedule = SupplementSchedule.none;

    if (food.sourceMetadataJson != null &&
        food.sourceMetadataJson!.isNotEmpty) {
      try {
        final meta =
            jsonDecode(food.sourceMetadataJson!) as Map<String, dynamic>;
        final rawNutrients = meta['nutrients'];
        if (rawNutrients is Map) {
          rawNutrients.forEach((k, v) {
            if (k is String && v is num && v > 0) {
              nutrients[k] = v.toDouble();
            }
          });
        }
        final rawSchedule = meta['schedule'] as String?;
        if (rawSchedule != null) {
          schedule = SupplementScheduleX.fromId(rawSchedule);
        }
      } catch (_) {}
    }

    if (food.sodiumMgPer100g != null && food.sodiumMgPer100g! > 0) {
      nutrients.putIfAbsent('sodium', () => food.sodiumMgPer100g!);
    }
    if (food.potassiumMgPer100g != null && food.potassiumMgPer100g! > 0) {
      nutrients.putIfAbsent('potassium', () => food.potassiumMgPer100g!);
    }

    final unit =
        (food.servingUnit != null &&
            supplementDoseUnits.contains(food.servingUnit))
        ? food.servingUnit!
        : 'g';
    final dose = food.servingAmount ?? food.servingGrams;

    return Supplement(
      id: const Uuid().v4(),
      name: food.name,
      brand: food.brand,
      barcode: barcode,
      doseAmount: dose != null && dose > 0 ? dose : 5,
      doseUnit: unit,
      nutrients: nutrients,
      schedule: schedule,
    );
  }

  Supplement _supplementFromPublicProduct(
    PublicProduct product,
    String barcode,
  ) {
    final nutrients = <String, double>{};
    if (product.fiberPer100g != null && product.fiberPer100g! > 0) {
      nutrients['fiber'] = product.fiberPer100g!;
    }
    if (product.sodiumMgPer100g != null && product.sodiumMgPer100g! > 0) {
      nutrients['sodium'] = product.sodiumMgPer100g!;
    }
    if (product.potassiumMgPer100g != null && product.potassiumMgPer100g! > 0) {
      nutrients['potassium'] = product.potassiumMgPer100g!;
    }

    return Supplement(
      id: const Uuid().v4(),
      name: product.name,
      brand: product.brand,
      barcode: barcode,
      doseAmount: product.servingGrams != null && product.servingGrams! > 0
          ? product.servingGrams
          : 5,
      doseUnit: 'g',
      nutrients: nutrients,
    );
  }

  Supplement _supplementFromRemoteFood(RemoteFood remote, String barcode) {
    final nutrients = <String, double>{};
    if (remote.fiberPer100g != null && remote.fiberPer100g! > 0) {
      nutrients['fiber'] = remote.fiberPer100g!;
    }
    return Supplement(
      id: const Uuid().v4(),
      name: remote.name,
      brand: remote.brand,
      barcode: barcode,
      doseAmount: remote.servingGrams != null && remote.servingGrams! > 0
          ? remote.servingGrams
          : 5,
      doseUnit: 'g',
      nutrients: nutrients,
    );
  }
}
