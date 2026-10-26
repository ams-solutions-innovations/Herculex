import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';
import 'package:herculex/features/nutrition/domain/food_portion.dart';
import 'package:herculex/features/nutrition/domain/recipe_text_parser.dart';
import 'package:herculex/features/nutrition/presentation/widgets/rambler_recipe_input_section.dart';
import 'package:herculex/features/nutrition/presentation/widgets/rambler_recipe_item_card.dart';
import 'package:herculex/features/nutrition/presentation/widgets/rambler_recipe_summary_card.dart';

export 'package:herculex/features/nutrition/domain/recipe_text_parser.dart'
    show RamblerRecipeResult;

/// Bottom sheet dialog for describing a recipe using Rambler AI (voice or text),
/// automatically parsing individual food items, setting servings & serving size,
/// and allowing manual adjustments before saving.
class RamblerRecipeDialog extends ConsumerStatefulWidget {
  final int? existingRecipeId;
  final String? initialRecipeName;
  final int? initialServings;
  final String? initialNotes;

  const RamblerRecipeDialog({
    super.key,
    this.existingRecipeId,
    this.initialRecipeName,
    this.initialServings,
    this.initialNotes,
  });

  static Future<RamblerRecipeResult?> show(
    BuildContext context, {
    int? existingRecipeId,
    String? initialRecipeName,
    int? initialServings,
    String? initialNotes,
  }) {
    return showModalBottomSheet<RamblerRecipeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RamblerRecipeDialog(
        existingRecipeId: existingRecipeId,
        initialRecipeName: initialRecipeName,
        initialServings: initialServings,
        initialNotes: initialNotes,
      ),
    );
  }

  @override
  ConsumerState<RamblerRecipeDialog> createState() =>
      _RamblerRecipeDialogState();
}

class _RamblerRecipeDialogState extends ConsumerState<RamblerRecipeDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  int _servings = 1;
  bool _isAnalyzing = false;
  bool _isSaving = false;
  String? _error;
  RamblerFoodResult? _result;
  List<RamblerFoodItem> _editableItems = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  SpeechToTextService? _stt;

  @override
  void initState() {
    super.initState();
    _servings = widget.initialServings ?? 1;
    if (_servings < 1) _servings = 1;
    _nameCtrl.text = widget.initialRecipeName ?? '';
    _notesCtrl.text = widget.initialNotes ?? '';

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stt = ref.read(speechToTextServiceProvider);
      _stt!.initialize();
    });
  }

  @override
  void dispose() {
    final stt = _stt;
    if (stt != null && stt.isListening) {
      unawaited(stt.stopListening());
    }
    _pulseCtrl.dispose();
    _focusNode.dispose();
    _textCtrl.dispose();
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    final stt = ref.read(speechToTextServiceProvider);
    if (stt.isListening) {
      await stt.stopListening();
      Haptics.selection();
    } else {
      Haptics.medium();
      setState(() => _error = null);
      await stt.startListening(
        localeId: stt.selectedLocaleId,
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() {
            _textCtrl.text = text;
            _textCtrl.selection =
                TextSelection.fromPosition(TextPosition(offset: text.length));
          });
        },
      );
    }
  }

  Future<void> _analyzeRecipe() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please enter or speak your recipe ingredients.');
      return;
    }

    final stt = ref.read(speechToTextServiceProvider);
    if (stt.isListening) await stt.stopListening();

    Haptics.selection();
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });

    try {
      final analyzer = ref.read(geminiFoodAnalyzerServiceProvider);
      RamblerFoodResult result;
      try {
        result = await analyzer.analyzeRamblerText(text: text);
      } catch (e) {
        final fallback = RecipeTextParser.fallbackParseItems(text);
        if (fallback.isNotEmpty) {
          final repo = ref.read(nutritionRepositoryProvider);
          var unmatchedCount = 0;
          for (final item in fallback) {
            final matches = await repo.searchFoods(item.name);
            if (matches.isNotEmpty) {
              final best = matches.firstWhere(
                (f) => f.name.toLowerCase() == item.name.toLowerCase(),
                orElse: () => matches.first,
              );
              item.kcalPer100g = best.kcalPer100g;
              item.proteinPer100g = best.proteinPer100g;
              item.carbsPer100g = best.carbsPer100g;
              item.fatPer100g = best.fatPer100g;
            } else {
              unmatchedCount++;
            }
          }
          result = RamblerFoodResult(
            summary: RecipeTextParser.parseTitle(text, null),
            items: fallback,
          );
          if (mounted) {
            AppNotice.show(
              context,
              unmatchedCount > 0
                  ? 'Offline mode: matched ${fallback.length - unmatchedCount}/${fallback.length} ingredients. Enter macros for remaining items.'
                  : 'Offline mode: matched ingredients from local food database. Review macros below.',
              kind: AppNoticeKind.info,
            );
          }
        } else {
          rethrow;
        }
      }

      if (!mounted) return;

      final parsedServings = RecipeTextParser.parseServings(
        text,
        fallback: _servings,
      );
      final parsedName = RecipeTextParser.parseTitle(text, result.summary);
      final parsedInstructions = RecipeTextParser.parseInstructions(text);

      setState(() {
        _isAnalyzing = false;
        _result = result;
        _editableItems = List.from(result.items);
        if (_nameCtrl.text.trim().isEmpty && parsedName.isNotEmpty) {
          _nameCtrl.text = parsedName;
        }
        if (parsedServings > 0 && widget.initialServings == null) {
          _servings = parsedServings;
        }
        if (_notesCtrl.text.trim().isEmpty && parsedInstructions != null) {
          _notesCtrl.text = parsedInstructions;
        }
      });
      Haptics.success();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
      Haptics.heavy();
    }
  }

  Future<void> _saveAndApply() async {
    if (_editableItems.isEmpty) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final recipeName = _nameCtrl.text.trim().isEmpty
          ? 'Rambler Recipe'
          : _nameCtrl.text.trim();
      final instructions =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      final servings = _servings > 0 ? _servings : 1;

      final targetRecipeId = await repo.saveRamblerRecipe(
        existingRecipeId: widget.existingRecipeId,
        name: recipeName,
        servings: servings,
        notes: instructions,
        ingredients: [
          for (final item in _editableItems)
            (
              name: item.name,
              kcalPer100g: item.kcalPer100g,
              proteinPer100g: item.proteinPer100g,
              carbsPer100g: item.carbsPer100g,
              fatPer100g: item.fatPer100g,
              servingGrams: item.servingGrams,
              portionAmount: item.portionAmount,
              portionUnit: item.portionUnit,
              servingLabel: FoodPortion.labelFor(
                amount: item.portionAmount,
                unit: item.portionUnit,
                mass: item.servingGrams,
              ),
            ),
        ],
      );

      Haptics.success();
      if (!mounted) return;

      Navigator.of(context).pop(
        RamblerRecipeResult(
          recipeId: targetRecipeId,
          recipeName: recipeName,
          servings: servings,
          instructions: instructions,
          items: _editableItems,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Failed to save recipe: $e';
      });
      Haptics.heavy();
    }
  }

  void _addNewItem() {
    setState(() {
      _editableItems.add(
        RamblerFoodItem(
          name: 'New ingredient',
          servingGrams: 100,
          portionAmount: 100,
          portionUnit: 'g',
          kcalPer100g: 100,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 2,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final stt = ref.watch(speechToTextServiceProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hx.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hx.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: hx.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rambler AI Recipe Builder',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold, color: hx.onSurface)),
                        Text('Say or type ingredients & servings',
                            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (_editableItems.isEmpty && _result == null)
                    RamblerRecipeInputSection(
                      controller: _textCtrl,
                      focusNode: _focusNode,
                      pulseAnimation: _pulseAnim,
                      isListening: stt.isListening,
                      languageOption: stt.selectedLanguageOption,
                      onToggleListening: _toggleListening,
                      onPromptSelected: (prompt) {
                        setState(() {
                          _textCtrl.text = prompt;
                          _error = null;
                        });
                      },
                    )
                  else
                    _buildResultsSection(theme, hx),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade700),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade200, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildBottomBar(hx),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection(ThemeData theme, HxColors hx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recipe Name',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: hx.secondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'e.g. Chicken Rice Bowl',
            filled: true,
            fillColor: hx.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.35)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 14),
        RamblerRecipeSummaryCard(
          items: _editableItems,
          servings: _servings,
          onServingsChanged: (val) => setState(() => _servings = val),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ingredients (${_editableItems.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Item'),
              style: TextButton.styleFrom(foregroundColor: hx.primary),
              onPressed: _addNewItem,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _editableItems.length; i++)
          RamblerRecipeItemCard(
            item: _editableItems[i],
            onChanged: () => setState(() {}),
            onDelete: () => setState(() => _editableItems.removeAt(i)),
          ),
        const SizedBox(height: 14),
        Text(
          'Directions & Preparation (Optional)',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: hx.secondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Add cooking instructions or tips…',
            filled: true,
            fillColor: hx.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.35)),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Re-enter / Edit Prompt'),
            onPressed: () => setState(() {
              _result = null;
              _editableItems = [];
              _error = null;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(HxColors hx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: _editableItems.isEmpty && _result == null
              ? FilledButton.icon(
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isAnalyzing ? 'Analyzing Recipe with AI…' : 'Analyze Recipe with Rambler AI',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: hx.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: _isAnalyzing ? null : _analyzeRecipe,
                )
              : FilledButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _isSaving
                        ? 'Saving Recipe…'
                        : (widget.existingRecipeId != null
                            ? 'Add ${_editableItems.length} Ingredients to Recipe'
                            : 'Create Recipe (${_editableItems.length} items)'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: _isSaving || _editableItems.isEmpty ? null : _saveAndApply,
                ),
        ),
      ),
    );
  }
}
