part of '../profile_view.dart';

class _AvatarHeader extends StatelessWidget {
  final Profile? profile;
  final VoidCallback onEdit;

  const _AvatarHeader({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.name?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onEdit,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: context.hx.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.hx.primary.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: name.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: 48,
                        color: context.hx.primary,
                      )
                    : Text(
                        name[0].toUpperCase(),
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: context.hx.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.hx.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.edit, size: 14, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onEdit,
          child: Text(
            name.isEmpty ? 'My Profile' : name,
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile != null ? profile!.activityLevel.label : 'Set your stats',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.hx.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Name editor reached by tapping the avatar. Picture selection is offered
/// here too; it is currently a placeholder because the profile model stores no
/// image path yet.
class _IdentitySheet extends StatefulWidget {
  final String initialName;
  const _IdentitySheet({required this.initialName});

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HxSheet(
      scrollable: false,
      title: 'Edit profile',
      padding: EdgeInsets.fromLTRB(
        HxSpace.x5,
        0,
        HxSpace.x5,
        HxSpace.x5 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: const StadiumBorder(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── BMI chip ──────────────────────────────────────────────────────────────────

class _BmiChip extends StatelessWidget {
  final double weightKg;
  final double heightCm;
  const _BmiChip({required this.weightKg, required this.heightCm});

  @override
  Widget build(BuildContext context) {
    final h = heightCm / 100;
    final bmi = weightKg / (h * h);
    final (label, color) = switch (bmi) {
      < 18.5 => ('Underweight', Colors.blue.shade400),
      < 25.0 => ('Healthy weight', Colors.green.shade600),
      < 30.0 => ('Overweight', Colors.orange.shade600),
      _ => ('Obese', Colors.red.shade600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'BMI ${bmi.toStringAsFixed(1)} · $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Save button ───────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: saving ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: context.hx.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
      ),
      child: saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Save Profile',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.hx.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Stat text field ───────────────────────────────────────────────────────────

class _StatField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// One quiet line under the field, e.g. where the number comes from.
  final String? helper;

  /// Every remaining stat field is numeric — the name moved into the avatar
  /// editor, so there is no free-text variant left to configure.
  static const keyboardType = TextInputType.numberWithOptions(decimal: true);

  const _StatField({
    required this.label,
    required this.hint,
    required this.controller,
    this.onChanged,
    this.focusNode,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.hx.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          keyboardType: keyboardType,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.hx.outline, fontSize: 13),
            filled: true,
            fillColor: context.hx.surfaceContainer,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide(color: context.hx.primary, width: 1.5),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.hx.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Pill toggle button ────────────────────────────────────────────────────────

class _PillToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? context.hx.primary : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: selected
                ? context.hx.primary
                : context.hx.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : context.hx.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Settings card / tile helpers ──────────────────────────────────────────────
