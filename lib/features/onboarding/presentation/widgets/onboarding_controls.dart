import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Title + supporting line at the top of a step.
class OnboardingHeading extends StatelessWidget {
  const OnboardingHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.headlineMedium?.copyWith(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: hx.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: HxSpace.x2),
          Text(
            subtitle!,
            style: text.bodyMedium?.copyWith(
              color: hx.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

/// Single-choice card with a radio mark: goal and activity lists.
class OnboardingOptionCard extends StatelessWidget {
  const OnboardingOptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.description,
    this.badge,
  });

  final String title;
  final String? description;

  /// Small pill next to the title, e.g. "Recommended".
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 19 : 20,
            vertical: selected ? 15 : 16,
          ),
          decoration: BoxDecoration(
            color: selected
                ? hx.primary.withValues(alpha: 0.10)
                : hx.surfaceContainerLowest,
            borderRadius: HxRadius.xlAll,
            border: Border.all(
              color: selected ? hx.primary : hx.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? hx.primary : hx.outline,
              ),
              const SizedBox(width: HxSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: text.titleMedium?.copyWith(
                              color: hx.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: HxSpace.x2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: hx.primaryContainer,
                              borderRadius: HxRadius.pillAll,
                            ),
                            child: Text(
                              badge!.toUpperCase(),
                              style: text.labelSmall?.copyWith(
                                color: hx.primaryText,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: text.bodySmall?.copyWith(
                          color: hx.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled text field with an optional trailing unit ("kg", "cm").
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.unit,
    this.optional = false,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLength,
    this.suffix,
    this.autofillHints,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? unit;
  final bool optional;
  final TextInputType keyboardType;
  final bool obscureText;
  final int? maxLength;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: HxRadius.smAll,
      borderSide: BorderSide(color: c, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: text.labelLarge?.copyWith(
              color: hx.onSurface,
              fontWeight: FontWeight.w700,
            ),
            children: [
              if (optional)
                TextSpan(
                  text: ' (optional)',
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        TextField(
          controller: controller,
          obscureText: obscureText,
          maxLength: maxLength,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            filled: true,
            fillColor: hx.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            suffixText: unit,
            suffixStyle: TextStyle(color: hx.onSurfaceVariant),
            suffixIcon: suffix,
            border: border(hx.outlineVariant),
            enabledBorder: border(hx.outlineVariant.withValues(alpha: 0.6)),
            focusedBorder: border(hx.primary, 1.5),
          ),
        ),
      ],
    );
  }
}

/// Pill-shaped segmented switch (Metric / Freedom, Male / Female).
class OnboardingSegmented<T> extends StatelessWidget {
  const OnboardingSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.expand = true,
  });

  /// Value → label, in display order.
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final segments = [
      for (final entry in options.entries)
        _segment(context, hx, text, entry.key, entry.value),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: hx.surfaceVariant,
        borderRadius: HxRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: segments,
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    HxColors hx,
    TextTheme text,
    T key,
    String label,
  ) {
    final selected = key == value;
    final child = Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? hx.primary : Colors.transparent,
            borderRadius: HxRadius.pillAll,
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: selected ? hx.onPrimary : hx.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: child) : child;
  }
}
