import 'package:flutter/material.dart';

class PremiumTextField extends StatelessWidget {
  final String hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final TextEditingController? controller;
  final int maxLines;

  const PremiumTextField({
    super.key,
    required this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.controller,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Theme.of(context).textTheme.bodyMedium?.color) : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      ),
    );
  }
}
