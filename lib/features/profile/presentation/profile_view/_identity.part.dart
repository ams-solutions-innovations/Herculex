part of '../profile_view.dart';

class _AvatarHeader extends StatelessWidget {
  final Profile? profile;
  final String? avatarId;
  final VoidCallback onEdit;
  final VoidCallback onPickAvatar;

  const _AvatarHeader({
    required this.profile,
    required this.avatarId,
    required this.onEdit,
    required this.onPickAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.name?.trim() ?? '';
    final avatar = GreekAvatars.findById(avatarId ?? profile?.avatarId);
    final accent = avatar?.accentColor ?? context.hx.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onPickAvatar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              GreekAvatarBadge(
                avatarId: avatar?.id,
                name: name,
                size: 108,
                showGlow: true,
                borderWidth: 2.5,
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2.2,
                  ),
                ),
                child: Icon(
                  avatar != null ? Icons.auto_awesome_rounded : Icons.edit,
                  size: 15,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onEdit,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name.isEmpty ? 'My Profile' : name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: context.hx.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (avatar != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onPickAvatar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    '${avatar.name} · ${avatar.title}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onPickAvatar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: context.hx.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: context.hx.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: context.hx.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Choose Greek god / titan',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: context.hx.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
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

class _IdentityResult {
  final String name;
  final String? avatarId;
  const _IdentityResult({required this.name, required this.avatarId});
}

/// Name & Greek avatar editor reached by tapping the name or edit button.
class _IdentitySheet extends StatefulWidget {
  final String initialName;
  final String? initialAvatarId;
  const _IdentitySheet({required this.initialName, this.initialAvatarId});

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialName,
  );
  late String? _avatarId = widget.initialAvatarId;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _openAvatarPicker() async {
    final res = await GreekAvatarPickerSheet.show(
      context,
      currentAvatarId: _avatarId,
      userName: _ctrl.text,
    );
    if (res == null || !mounted) return;
    setState(() => _avatarId = res.avatarId);
  }

  void _submit() {
    Navigator.of(
      context,
    ).pop(_IdentityResult(name: _ctrl.text.trim(), avatarId: _avatarId));
  }

  @override
  Widget build(BuildContext context) {
    final avatar = GreekAvatars.findById(_avatarId);
    final theme = Theme.of(context);

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
          Center(
            child: GestureDetector(
              onTap: _openAvatarPicker,
              child: Column(
                children: [
                  GreekAvatarBadge(
                    avatarId: _avatarId,
                    name: _ctrl.text,
                    size: 76,
                    showGlow: true,
                    borderWidth: 2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    avatar != null
                        ? '${avatar.name} · Change avatar'
                        : 'Choose profile picture (Greek gods & titans)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: avatar?.accentColor ?? context.hx.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
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

/// Biological sex as a row that opens a menu, styled like the activity-level
/// row, with a male / female icon on each option.
class _SexDropdown extends StatelessWidget {
  final BiologicalSex? selected;
  final ValueChanged<BiologicalSex> onChanged;
  const _SexDropdown({required this.selected, required this.onChanged});

  static IconData _icon(BiologicalSex sex) => switch (sex) {
    BiologicalSex.male => Icons.male_rounded,
    BiologicalSex.female => Icons.female_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final current = selected;
    return PopupMenuButton<BiologicalSex>(
      tooltip: 'Biological sex',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final sex in BiologicalSex.values)
          PopupMenuItem(
            value: sex,
            child: Row(
              children: [
                Icon(_icon(sex), size: 20, color: hx.primary),
                const SizedBox(width: 10),
                Text(
                  sex.label,
                  style: TextStyle(
                    fontWeight: sex == current
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              current == null ? Icons.person_outline_rounded : _icon(current),
              color: hx.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Biological sex',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Text(
              current?.label ?? 'Select',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: hx.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
