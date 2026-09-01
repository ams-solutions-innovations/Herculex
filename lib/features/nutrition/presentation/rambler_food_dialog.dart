import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/fasting/presentation/fasting_food_log_dialog.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';
import 'package:herculex/features/nutrition/presentation/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';

class RamblerFoodDialog extends ConsumerStatefulWidget {
  final DateTime date;
  final String? initialMealKey;

  const RamblerFoodDialog({super.key, required this.date, this.initialMealKey});

  static Future<bool?> show(
    BuildContext context, {
    required DateTime date,
    String? initialMealKey,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RamblerFoodDialog(date: date, initialMealKey: initialMealKey),
    );
  }

  @override
  ConsumerState<RamblerFoodDialog> createState() => _RamblerFoodDialogState();
}

class _RamblerFoodDialogState extends ConsumerState<RamblerFoodDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  late String _selectedMealKey;

  bool _isAnalyzing = false;
  bool _isSaving = false;
  String? _error;
  RamblerFoodResult? _result;
  List<RamblerFoodItem> _editableItems = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _selectedMealKey = widget.initialMealKey ?? 'lunch';

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.25,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Pre-initialize STT
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(speechToTextServiceProvider).initialize();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _textCtrl.dispose();
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
        onResult: (recognizedText, isFinal) {
          if (!mounted) return;
          setState(() {
            _textCtrl.text = recognizedText;
            _textCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _textCtrl.text.length),
            );
          });
        },
      );
    }
  }

  Future<void> _analyzeWithGemini() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Vnesite ali povejte kaj ste jedli.');
      return;
    }

    final stt = ref.read(speechToTextServiceProvider);
    if (stt.isListening) {
      await stt.stopListening();
    }

    Haptics.selection();
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });

    try {
      final analyzer = ref.read(geminiFoodAnalyzerServiceProvider);
      final result = await analyzer.analyzeRamblerText(
        text: text,
        preferredMealKey: _selectedMealKey,
      );

      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _result = result;
        _editableItems = List.from(result.items);
        if (result.suggestedMealKey != null &&
            result.suggestedMealKey!.isNotEmpty) {
          _selectedMealKey = result.suggestedMealKey!;
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

  Future<void> _logAllItems() async {
    if (_editableItems.isEmpty) return;

    final proceed = await confirmEndFastOnFoodLog(context, ref);
    if (!proceed || !mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final repo = ref.read(nutritionRepositoryProvider);

      for (final item in _editableItems) {
        final food = await repo.createCustomFood(
          name: item.name,
          brand: 'Rambler AI',
          kcalPer100g: item.kcalPer100g,
          proteinPer100g: item.proteinPer100g,
          carbsPer100g: item.carbsPer100g,
          fatPer100g: item.fatPer100g,
          servingGrams: item.servingGrams,
          servingLabel: '${item.servingGrams.toStringAsFixed(0)} g',
        );

        await repo.logFood(
          date: widget.date,
          mealKey: _selectedMealKey,
          foodId: food.id,
          grams: item.servingGrams,
        );
      }

      Haptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Napaka pri shranjevanju: $e';
      });
      Haptics.heavy();
    }
  }

  void _addNewItem() {
    setState(() {
      _editableItems.add(
        RamblerFoodItem(
          name: 'Novo živilo',
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
    final stt = ref.watch(speechToTextServiceProvider);
    final slots = ref.watch(mealSlotsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // ── Header Bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.mic, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rambler AI Food Logger',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'Povej ali napiši kaj si jedel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
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
            const SizedBox(height: 12),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    'Obrok / Meal Slot',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMealSlotChips(slots),
                  const SizedBox(height: 16),

                  if (_result == null) ...[
                    _buildInputSection(stt, theme),
                  ] else ...[
                    _buildResultsSection(theme),
                  ],

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
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade300,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Colors.red.shade200,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSlotChips(List<MealSlot> slots) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final slot in slots)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(slot.label),
                selected: _selectedMealKey == slot.key,
                onSelected: (selected) {
                  if (selected) {
                    Haptics.selection();
                    setState(() => _selectedMealKey = slot.key);
                  }
                },
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: _selectedMealKey == slot.key
                      ? Colors.white
                      : AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                backgroundColor: AppColors.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputSection(SpeechToTextService stt, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: stt.isListening
                  ? AppColors.primary
                  : AppColors.outlineVariant.withValues(alpha: 0.4),
              width: stt.isListening ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _textCtrl,
                maxLines: 4,
                minLines: 3,
                style: const TextStyle(fontSize: 15, height: 1.4),
                decoration: InputDecoration(
                  hintText: stt.selectedLocaleId.toLowerCase().startsWith('sl')
                      ? 'Npr. "Za kosilo sem pojedel 200g piščančjih prsi, 150g riža in skledo zelene solate z oljem..."'
                      : 'E.g. "I had 2 scrambled eggs on whole wheat toast with half an avocado and black coffee..."',
                  hintStyle: TextStyle(
                    color: AppColors.secondary.withValues(alpha: 0.6),
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_textCtrl.text.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Počisti'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          Haptics.selection();
                          setState(() => _textCtrl.clear());
                        },
                      )
                    else
                      const SizedBox.shrink(),
                    if (stt.isListening)
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fiber_manual_record,
                                color: Colors.redAccent,
                                size: 10,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Poslušam...',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _toggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stt.isListening
                        ? Colors.redAccent
                        : AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (stt.isListening
                                    ? Colors.redAccent
                                    : AppColors.primary)
                                .withValues(alpha: 0.4),
                        blurRadius: stt.isListening ? 20 : 12,
                        spreadRadius: stt.isListening ? 4 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    stt.isListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                stt.isListening
                    ? 'Kliknite za ustavitev'
                    : 'Pritisnite za govor (STT)',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: stt.isListening
                      ? Colors.redAccent
                      : AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSection(ThemeData theme) {
    final totalKcal = _editableItems.fold<double>(0, (s, i) => s + i.totalKcal);
    final totalP = _editableItems.fold<double>(0, (s, i) => s + i.totalProtein);
    final totalC = _editableItems.fold<double>(0, (s, i) => s + i.totalCarbs);
    final totalF = _editableItems.fold<double>(0, (s, i) => s + i.totalFat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_result?.summary != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _result!.summary!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Prepoznana živila (${_editableItems.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Dodaj živilo'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _addNewItem,
            ),
          ],
        ),
        const SizedBox(height: 8),

        for (int i = 0; i < _editableItems.length; i++)
          _buildItemCard(_editableItems[i], i, theme),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Skupaj za ta obrok',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${totalKcal.round()} kcal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.macroKcal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MacroTotalColumn(
                    label: 'Beljakovine',
                    value: '${totalP.toStringAsFixed(1)}g',
                    color: AppColors.macroProtein,
                  ),
                  _MacroTotalColumn(
                    label: 'Ogljikovi hidrati',
                    value: '${totalC.toStringAsFixed(1)}g',
                    color: AppColors.macroCarbs,
                  ),
                  _MacroTotalColumn(
                    label: 'Maščobe',
                    value: '${totalF.toStringAsFixed(1)}g',
                    color: AppColors.macroFat,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Ponovni vnos / Spremeni besedilo'),
            onPressed: () {
              setState(() => _result = null);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(RamblerFoodItem item, int index, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.name,
                  onChanged: (val) => item.name = val,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red.shade300,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Haptics.selection();
                  setState(() => _editableItems.removeAt(index));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Text(
                'Količina:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              _GramAdjustButton(
                icon: Icons.remove,
                onTap: () {
                  if (item.servingGrams > 10) {
                    Haptics.selection();
                    setState(() {
                      item.servingGrams -= 25;
                      if (item.servingGrams < 10) item.servingGrams = 10;
                      item.portionAmount = item.servingGrams;
                    });
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '${item.servingGrams.toStringAsFixed(0)} ${item.portionUnit}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              _GramAdjustButton(
                icon: Icons.add,
                onTap: () {
                  Haptics.selection();
                  setState(() {
                    item.servingGrams += 25;
                    item.portionAmount = item.servingGrams;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.macroKcal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.totalKcal.round()} kcal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.macroKcal,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _MacroPill(
                'P',
                '${item.totalProtein.toStringAsFixed(1)}g',
                AppColors.macroProtein,
              ),
              const SizedBox(width: 6),
              _MacroPill(
                'C',
                '${item.totalCarbs.toStringAsFixed(1)}g',
                AppColors.macroCarbs,
              ),
              const SizedBox(width: 6),
              _MacroPill(
                'F',
                '${item.totalFat.toStringAsFixed(1)}g',
                AppColors.macroFat,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: _result == null
              ? FilledButton.icon(
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isAnalyzing
                        ? 'Razčlenjujem z Gemini AI...'
                        : 'Analiziraj z Gemini AI',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: _isAnalyzing ? null : _analyzeWithGemini,
                )
              : FilledButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _isSaving
                        ? 'Shranjujem v dnevnik...'
                        : 'Vnesi v dnevnik (${_editableItems.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: _isSaving || _editableItems.isEmpty
                      ? null
                      : _logAllItems,
                ),
        ),
      ),
    );
  }
}

class _GramAdjustButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GramAdjustButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.onSurface),
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _MacroTotalColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroTotalColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.secondary)),
      ],
    );
  }
}
