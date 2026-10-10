import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';

/// Bottom sheet for choosing the speech-to-text language.
void showSttLanguagePicker(BuildContext context, WidgetRef ref) {
  Haptics.selection();
  final stt = ref.read(speechToTextServiceProvider);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.hx.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Govor v besedilo / STT Jezik',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: kSupportedSttLanguages.length,
                itemBuilder: (ctx, i) {
                  final lang = kSupportedSttLanguages[i];
                  final isSelected =
                      lang.localeId.toLowerCase() ==
                      stt.selectedLocaleId.toLowerCase();
                  return ListTile(
                    leading: Text(
                      lang.flag,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(
                      lang.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? ctx.hx.primary : null,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: ctx.hx.primary)
                        : null,
                    onTap: () async {
                      Haptics.selection();
                      await ref
                          .read(speechToTextServiceProvider)
                          .setLocale(lang.localeId);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
