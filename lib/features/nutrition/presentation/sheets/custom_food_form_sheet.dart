import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/nutrition_label_ocr_service.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/nutrition/domain/food_portion.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:image_picker/image_picker.dart';

class CustomFoodFormSheet extends ConsumerStatefulWidget {
  final String? initialName;
  final String? initialBarcode;
  final FoodData? existingFood;
  final bool autoStartAiScan;

  const CustomFoodFormSheet({
    super.key,
    this.initialName,
    this.initialBarcode,
    this.existingFood,
    this.autoStartAiScan = false,
  });

  static Future<FoodData?> show(
    BuildContext context, {
    String? initialName,
    String? initialBarcode,
    FoodData? existingFood,
    bool autoStartAiScan = false,
  }) {
    return showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: CustomFoodFormSheet(
          initialName: initialName,
          initialBarcode: initialBarcode,
          existingFood: existingFood,
          autoStartAiScan: autoStartAiScan,
        ),
      ),
    );
  }

  @override
  ConsumerState<CustomFoodFormSheet> createState() =>
      _CustomFoodFormSheetState();
}

class _CustomFoodFormSheetState extends ConsumerState<CustomFoodFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _barcode;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _servingAmount;
  late final TextEditingController _servingUnit;
  late final TextEditingController _servingG;
  late final TextEditingController _sodium;
  late final TextEditingController _potassium;
  late final TextEditingController _cholesterol;

  // Additional expanded nutrient controllers
  late final TextEditingController _sugars;
  late final TextEditingController _transFat;
  late final TextEditingController _saturatedFat;
  late final TextEditingController _fiber;
  late final TextEditingController _calcium;
  late final TextEditingController _iron;
  late final TextEditingController _vitaminC;
  late final TextEditingController _vitaminD;
  late final TextEditingController _zinc;
  late final TextEditingController _magnesium;
  late final TextEditingController _manganese;
  late final TextEditingController _selenium;
  late final TextEditingController _phosphorus;
  late final TextEditingController _copper;

  bool _saving = false;
  bool _scanningAi = false;
  String? _aiScanStatus;
  String? _error;
  late String _referenceBasis;

  @override
  void initState() {
    super.initState();
    final ef = widget.existingFood;
    _name = TextEditingController(text: ef?.name ?? widget.initialName ?? '');
    _brand = TextEditingController(text: ef?.brand ?? '');
    _barcode = TextEditingController(
      text: ef?.barcode ?? widget.initialBarcode ?? '',
    );
    _kcal = TextEditingController(
      text: ef != null ? ef.kcalPer100g.toStringAsFixed(0) : '',
    );
    _protein = TextEditingController(
      text: ef != null ? ef.proteinPer100g.toStringAsFixed(1) : '',
    );
    _carbs = TextEditingController(
      text: ef != null ? ef.carbsPer100g.toStringAsFixed(1) : '',
    );
    _fat = TextEditingController(
      text: ef != null ? ef.fatPer100g.toStringAsFixed(1) : '',
    );
    _referenceBasis = ef?.referenceBasis == '100 ml' ? '100 ml' : '100 g';
    _servingAmount = TextEditingController(
      text: ef == null
          ? '100'
          : FoodPortion.defaultAmount(
              ef,
            ).toStringAsFixed(FoodPortion.defaultAmount(ef) % 1 == 0 ? 0 : 1),
    );
    _servingUnit = TextEditingController(
      text: ef == null ? 'g' : FoodPortion.defaultUnit(ef),
    );
    _servingG = TextEditingController(
      text: ef?.servingGrams != null
          ? ef!.servingGrams!.toStringAsFixed(0)
          : (ef == null ? '100' : ''),
    );
    _sodium = TextEditingController(
      text: ef?.sodiumMgPer100g != null
          ? ef!.sodiumMgPer100g!.toStringAsFixed(0)
          : '',
    );
    _potassium = TextEditingController(
      text: ef?.potassiumMgPer100g != null
          ? ef!.potassiumMgPer100g!.toStringAsFixed(0)
          : '',
    );
    _cholesterol = TextEditingController(
      text: ef?.cholesterolMgPer100g != null
          ? ef!.cholesterolMgPer100g!.toStringAsFixed(0)
          : '',
    );

    // Parse existing sourceMetadataJson if available
    Map<String, dynamic> existingMicros = {};
    if (ef?.sourceMetadataJson != null) {
      try {
        final decoded = jsonDecode(ef!.sourceMetadataJson!);
        if (decoded is Map && decoded['nutrients'] is Map) {
          existingMicros = Map<String, dynamic>.from(decoded['nutrients']);
        }
      } catch (_) {}
    }

    String fmt(String key) {
      final val = existingMicros[key];
      if (val is num) return val.toString();
      return '';
    }

    final initialFiber = fmt('fiber').isNotEmpty
        ? fmt('fiber')
        : (ef?.fiberPer100g != null
              ? ef!.fiberPer100g!.toStringAsFixed(1)
              : '');

    _sugars = TextEditingController(text: fmt('sugars'));
    _transFat = TextEditingController(text: fmt('trans_fat'));
    _saturatedFat = TextEditingController(text: fmt('saturated_fat'));
    _fiber = TextEditingController(text: initialFiber);
    _calcium = TextEditingController(text: fmt('calcium'));
    _iron = TextEditingController(text: fmt('iron'));
    _vitaminC = TextEditingController(text: fmt('vitamin_c'));
    _vitaminD = TextEditingController(text: fmt('vitamin_d'));
    _zinc = TextEditingController(text: fmt('zinc'));
    _magnesium = TextEditingController(text: fmt('magnesium'));
    _manganese = TextEditingController(text: fmt('manganese'));
    _selenium = TextEditingController(text: fmt('selenium'));
    _phosphorus = TextEditingController(text: fmt('phosphorus'));
    _copper = TextEditingController(text: fmt('copper'));

    if (widget.autoStartAiScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanNutritionLabelWithAi();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _barcode,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _servingAmount,
      _servingUnit,
      _servingG,
      _sodium,
      _potassium,
      _cholesterol,
      _sugars,
      _transFat,
      _saturatedFat,
      _fiber,
      _calcium,
      _iron,
      _vitaminC,
      _vitaminD,
      _zinc,
      _magnesium,
      _manganese,
      _selenium,
      _phosphorus,
      _copper,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanNutritionLabelWithAi() async {
    if (_scanningAi) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Take photo of nutrition label'),
              subtitle: const Text(
                'Herculex AI reads calories, macros, and micronutrients from photo',
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _scanningAi = true;
      _error = null;
      _aiScanStatus = null;
    });

    try {
      final gemini = ref.read(geminiFoodAnalyzerServiceProvider);
      final draft = await NutritionLabelOcrService(
        gemini,
      ).extractWithAi(File(picked.path));
      if (!mounted) return;
      _applyLabelDraft(draft);
      setState(() {
        _scanningAi = false;
        _aiScanStatus =
            draft.warning ??
            'Nutritional values scanned with Herculex AI. Review and save.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanningAi = false;
        _error = 'AI scan failed: $e';
      });
    }
  }

  void _applyLabelDraft(NutritionLabelDraft draft) {
    final trimmedDraftName = draft.name.trim();
    if (_name.text.trim().isEmpty &&
        trimmedDraftName.isNotEmpty &&
        trimmedDraftName.toLowerCase() != 'scanned food') {
      _name.text = trimmedDraftName;
    } else if (_name.text.trim().isEmpty && trimmedDraftName.isNotEmpty) {
      _name.text = trimmedDraftName;
    }
    if (_brand.text.trim().isEmpty &&
        (draft.brand?.trim().isNotEmpty ?? false)) {
      _brand.text = draft.brand!.trim();
    }
    if (draft.servingUnit.trim().toLowerCase() == 'ml') {
      _referenceBasis = '100 ml';
    }
    if (draft.kcalPer100g != null) {
      _kcal.text = draft.kcalPer100g!.toStringAsFixed(0);
    }
    if (draft.proteinPer100g != null) {
      _protein.text = draft.proteinPer100g!.toStringAsFixed(1);
    }
    if (draft.carbsPer100g != null) {
      _carbs.text = draft.carbsPer100g!.toStringAsFixed(1);
    }
    if (draft.fatPer100g != null) {
      _fat.text = draft.fatPer100g!.toStringAsFixed(1);
    }
    if (draft.fiberPer100g != null) {
      _fiber.text = draft.fiberPer100g!.toStringAsFixed(1);
    }
    if (draft.sodiumMgPer100g != null) {
      _sodium.text = draft.sodiumMgPer100g!.toStringAsFixed(0);
    }
    if (draft.servingGrams != null && draft.servingGrams! > 0) {
      _servingG.text = draft.servingGrams!.toStringAsFixed(0);
    }
    if (draft.portionAmount != null && draft.portionAmount! > 0) {
      _servingAmount.text = draft.portionAmount!.toStringAsFixed(
        draft.portionAmount! % 1 == 0 ? 0 : 1,
      );
    }
    if (draft.servingUnit.trim().isNotEmpty) {
      _servingUnit.text = draft.servingUnit.trim();
    }

    void setMicro(TextEditingController ctrl, List<String> keys) {
      for (final k in keys) {
        final v = draft.microsPer100g[k];
        if (v != null) {
          ctrl.text = v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
          return;
        }
      }
    }

    setMicro(_sugars, ['sugars', 'sugar']);
    setMicro(_saturatedFat, ['saturated_fat', 'saturatedFat']);
    setMicro(_transFat, ['trans_fat', 'transFat']);
    setMicro(_potassium, ['potassium', 'potassium_mg']);
    setMicro(_cholesterol, ['cholesterol', 'cholesterol_mg']);
    setMicro(_calcium, ['calcium', 'calcium_mg']);
    setMicro(_iron, ['iron', 'iron_mg']);
    setMicro(_vitaminC, ['vitamin_c', 'vitaminC']);
    setMicro(_vitaminD, ['vitamin_d', 'vitaminD']);
    setMicro(_zinc, ['zinc', 'zinc_mg']);
    setMicro(_magnesium, ['magnesium', 'magnesium_mg']);
    setMicro(_manganese, ['manganese', 'manganese_mg']);
    setMicro(_selenium, ['selenium', 'selenium_ug']);
    setMicro(_phosphorus, ['phosphorus', 'phosphorus_mg']);
    setMicro(_copper, ['copper', 'copper_mg']);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = double.tryParse(_kcal.text.trim());
    if (name.isEmpty || kcal == null || kcal <= 0) {
      setState(() => _error = 'Name and kcal/100g are required');
      return;
    }
    final rawBarcode = _barcode.text.trim();
    final servingAmount = double.tryParse(_servingAmount.text.trim());
    final servingUnit = _servingUnit.text.trim();
    final servingGrams = double.tryParse(_servingG.text.trim());
    final normalizedBarcode = rawBarcode.isEmpty
        ? null
        : normalizeBarcode(rawBarcode);
    if (rawBarcode.isNotEmpty && normalizedBarcode == null) {
      setState(
        () =>
            _error = 'Barcode must be a valid EAN-8, UPC-A, EAN-13 or GTIN-14',
      );
      return;
    }
    if (servingAmount == null || servingAmount <= 0 || servingUnit.isEmpty) {
      setState(
        () => _error = 'Enter a positive default serving and its measure.',
      );
      return;
    }
    final isMassOrVolume =
        servingUnit.toLowerCase() == 'g' || servingUnit.toLowerCase() == 'ml';
    if (!isMassOrVolume && (servingGrams == null || servingGrams <= 0)) {
      setState(
        () => _error =
            'A named measure (for example scoop or nugget) needs its weight in grams.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final microsMap = <String, double>{};
    void addIfPresent(String key, TextEditingController ctrl) {
      final v = double.tryParse(ctrl.text.trim());
      if (v != null) microsMap[key] = v;
    }

    addIfPresent('sugars', _sugars);
    addIfPresent('trans_fat', _transFat);
    addIfPresent('saturated_fat', _saturatedFat);
    addIfPresent('fiber', _fiber);
    addIfPresent('calcium', _calcium);
    addIfPresent('iron', _iron);
    addIfPresent('vitamin_c', _vitaminC);
    addIfPresent('vitamin_d', _vitaminD);
    addIfPresent('zinc', _zinc);
    addIfPresent('magnesium', _magnesium);
    addIfPresent('manganese', _manganese);
    addIfPresent('selenium', _selenium);
    addIfPresent('phosphorus', _phosphorus);
    addIfPresent('copper', _copper);

    final metadataJson = microsMap.isNotEmpty
        ? jsonEncode({'nutrients': microsMap})
        : widget.existingFood?.sourceMetadataJson;

    final repo = ref.read(nutritionRepositoryProvider);
    final savedServingGrams =
        servingGrams ?? (isMassOrVolume ? servingAmount : null);
    final servingLabel = FoodPortion.labelFor(
      amount: servingAmount,
      unit: servingUnit,
      mass: savedServingGrams,
    );
    final fiberVal = double.tryParse(_fiber.text.trim());
    final FoodData food;
    if (widget.existingFood != null) {
      food = await repo.updateCustomFood(
        id: widget.existingFood!.id,
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        barcode: normalizedBarcode?.value,
        kcalPer100g: kcal,
        proteinPer100g: double.tryParse(_protein.text.trim()) ?? 0,
        carbsPer100g: double.tryParse(_carbs.text.trim()) ?? 0,
        fatPer100g: double.tryParse(_fat.text.trim()) ?? 0,
        fiberPer100g: fiberVal,
        servingGrams: savedServingGrams,
        servingLabel: servingLabel,
        referenceBasis: _referenceBasis,
        servingAmount: servingAmount,
        servingUnit: servingUnit,
        sourceMetadataJson: metadataJson,
        sodiumMgPer100g: double.tryParse(_sodium.text.trim()),
        potassiumMgPer100g: double.tryParse(_potassium.text.trim()),
        cholesterolMgPer100g: double.tryParse(_cholesterol.text.trim()),
      );
    } else {
      food = await repo.createCustomFood(
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        barcode: normalizedBarcode?.value,
        kcalPer100g: kcal,
        proteinPer100g: double.tryParse(_protein.text.trim()) ?? 0,
        carbsPer100g: double.tryParse(_carbs.text.trim()) ?? 0,
        fatPer100g: double.tryParse(_fat.text.trim()) ?? 0,
        fiberPer100g: fiberVal,
        servingGrams: savedServingGrams,
        servingLabel: servingLabel,
        referenceBasis: _referenceBasis,
        servingAmount: servingAmount,
        servingUnit: servingUnit,
        sourceMetadataJson: metadataJson,
        sodiumMgPer100g: double.tryParse(_sodium.text.trim()),
        potassiumMgPer100g: double.tryParse(_potassium.text.trim()),
        cholesterolMgPer100g: double.tryParse(_cholesterol.text.trim()),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingFood != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEditing ? 'Edit food' : 'Custom food',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Enter nutrition values in the selected 100 g/ml basis.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('scan_nutrition_ai_button'),
              onPressed: _scanningAi ? null : _scanNutritionLabelWithAi,
              icon: _scanningAi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.document_scanner_outlined,
                      color: AppColors.primary,
                    ),
              label: Text(
                _scanningAi
                    ? 'Analyzing nutrition label with AI…'
                    : 'Scan nutrition values with AI',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_aiScanStatus != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _aiScanStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _Field(label: 'Name *', controller: _name),
            const SizedBox(height: 14),
            _Field(label: 'Brand', controller: _brand),
            const SizedBox(height: 14),
            _Field(label: 'Barcode (optional)', controller: _barcode),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _referenceBasis,
              decoration: InputDecoration(
                labelText: 'Nutrition basis',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              items: const [
                DropdownMenuItem(value: '100 g', child: Text('Per 100 g')),
                DropdownMenuItem(value: '100 ml', child: Text('Per 100 ml')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _referenceBasis = value);
              },
            ),
            const SizedBox(height: 14),
            _Field(
              label: _referenceBasis == '100 ml'
                  ? 'kcal / 100 ml *'
                  : 'kcal / 100 g *',
              controller: _kcal,
              numeric: true,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Protein g',
                    controller: _protein,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Carbs g',
                    controller: _carbs,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Fat g',
                    controller: _fat,
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'DEFAULT SERVING',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Quantity',
                    controller: _servingAmount,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Measure (g, scoop, nugget…)',
                    controller: _servingUnit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Weight of this serving (g)',
              controller: _servingG,
              numeric: true,
            ),
            const SizedBox(height: 20),
            Text(
              'MINERALS (optional, per 100g)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Sodium mg',
                    controller: _sodium,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Potassium mg',
                    controller: _potassium,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Cholesterol mg',
                    controller: _cholesterol,
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Additional Nutrients (Sugars, Fats, Vitamins…)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Sugars g',
                          controller: _sugars,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Fiber g',
                          controller: _fiber,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Saturated Fat g',
                          controller: _saturatedFat,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Trans Fat g',
                          controller: _transFat,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Calcium mg',
                          controller: _calcium,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Iron mg',
                          controller: _iron,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Vitamin C mg',
                          controller: _vitaminC,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Vitamin D µg',
                          controller: _vitaminD,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Zinc mg',
                          controller: _zinc,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Magnesium mg',
                          controller: _magnesium,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Manganese mg',
                          controller: _manganese,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Selenium µg',
                          controller: _selenium,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Phosphorus mg',
                          controller: _phosphorus,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Copper mg',
                          controller: _copper,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 28),
            PremiumButton(
              text: _saving ? 'Saving…' : 'Save food',
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  const _Field({
    required this.label,
    required this.controller,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceVariant,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
