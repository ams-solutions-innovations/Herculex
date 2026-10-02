import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// The file behind a relative path, or null when the store rejects the path
/// or the file is gone. Never throws.
final _photoFileProvider = FutureProvider.autoDispose.family<File?, String>((
  ref,
  relativePath,
) async {
  try {
    final file = await ref
        .read(physiquePhotoStoreProvider)
        .resolve(relativePath);
    return await file.exists() ? file : null;
  } on Object {
    return null;
  }
});

/// A private check-in or baseline photo. The relative path is resolved at read
/// time through the photo store; a missing, empty or unsafe path shows a
/// placeholder instead of throwing. Not tappable.
class PhotoThumbnail extends ConsumerWidget {
  const PhotoThumbnail({
    super.key,
    required this.relativePath,
    this.width = 72,
    this.height = 96,
  });

  final String relativePath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final async = relativePath.isEmpty
        ? null
        : ref.watch(_photoFileProvider(relativePath));
    final file = async?.asData?.value;

    Widget placeholder() => Semantics(
      label: 'Photo unavailable',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(HxSpace.x1),
        color: hx.surfaceVariant,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 24,
              color: hx.tertiary,
            ),
            const SizedBox(height: HxSpace.x1),
            Flexible(
              child: Text(
                'Photo unavailable',
                textAlign: TextAlign.center,
                style: PhysiqueText.label(context, color: hx.tertiary),
              ),
            ),
          ],
        ),
      ),
    );

    return ClipRRect(
      borderRadius: HxRadius.smAll,
      child: SizedBox(
        width: width,
        height: height,
        child: (async != null && async.isLoading)
            ? ColoredBox(color: hx.surfaceVariant)
            : file == null
            ? placeholder()
            : Image.file(
                file,
                width: width,
                height: height,
                cacheWidth: (width * 2).round(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder(),
              ),
      ),
    );
  }
}
