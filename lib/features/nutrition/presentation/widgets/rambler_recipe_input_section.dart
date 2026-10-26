import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';

class RamblerRecipeInputSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Animation<double> pulseAnimation;
  final bool isListening;
  final SttLanguageOption languageOption;
  final VoidCallback onToggleListening;
  final ValueChanged<String> onPromptSelected;

  const RamblerRecipeInputSection({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.pulseAnimation,
    required this.isListening,
    required this.languageOption,
    required this.onToggleListening,
    required this.onPromptSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Describe your recipe',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: hx.secondary,
              ),
            ),
            Text(
              '${languageOption.flag} ${languageOption.name}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hx.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: hx.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: focusNode.hasFocus
                  ? hx.primary
                  : hx.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
                minLines: 3,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: hx.onSurface,
                  fontWeight: FontWeight.w400,
                ),
                cursorColor: hx.primary,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText:
                      'e.g. "Chicken Burrito Bowl: 250g grilled chicken, 150g brown rice, 80g black beans, 50g avocado, 15g salsa. Makes 2 servings. Assemble in a bowl."',
                  hintStyle: TextStyle(
                    color: hx.secondary.withValues(alpha: 0.65),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (controller.text.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Haptics.selection();
                          controller.clear();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: hx.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Clear',
                                style: TextStyle(
                                  color: hx.secondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (isListening)
                      ScaleTransition(
                        scale: pulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fiber_manual_record,
                                color: Colors.redAccent,
                                size: 9,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Listening...',
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
                onTap: onToggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening ? Colors.redAccent : hx.primary,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isListening ? Colors.redAccent : hx.primary)
                                .withValues(alpha: 0.35),
                        blurRadius: isListening ? 20 : 12,
                        spreadRadius: isListening ? 4 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isListening ? 'Tap to stop' : 'Tap to speak (Voice AI)',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isListening ? Colors.redAccent : hx.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Quick Prompt Examples',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: hx.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _exampleChip(
              context,
              'High Protein Oats',
              'Protein Oatmeal: 80g oats, 30g whey protein, 200ml almond milk, 15g peanut butter, 1 banana. 1 serving.',
            ),
            _exampleChip(
              context,
              'Chicken Pasta',
              'Chicken Penne: 300g chicken breast, 150g penne pasta, 15g olive oil, 50g parmesan. 2 servings.',
            ),
            _exampleChip(
              context,
              'Salmon Bowl',
              'Salmon Bowl: 200g salmon fillet, 150g white rice, 100g steamed broccoli. 1 serving.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _exampleChip(BuildContext context, String label, String prompt) {
    final hx = context.hx;
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.auto_awesome, size: 14),
      backgroundColor: hx.surfaceContainer,
      side: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.3)),
      labelStyle: TextStyle(fontSize: 12, color: hx.onSurface),
      onPressed: () {
        Haptics.selection();
        onPromptSelected(prompt);
      },
    );
  }
}
