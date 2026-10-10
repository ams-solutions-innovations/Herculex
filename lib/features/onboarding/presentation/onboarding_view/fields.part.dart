part of '../onboarding_view.dart';

/// Label-over-input field shared by the onboarding steps.
Widget _labeledField(
  String label,
  String hint,
  TextEditingController controller, {
  TextInputType keyboardType = TextInputType.text,
  bool obscureText = false,
  int? maxLength,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        obscureText: obscureText,
        maxLength: maxLength,
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        keyboardType: keyboardType,
      ),
    ],
  );
}
