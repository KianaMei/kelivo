
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../icons/lucide_adapter.dart';

class StorageImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const StorageImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: width != null ? (width! * MediaQuery.of(context).devicePixelRatio).round() : null,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          alignment: Alignment.center,
          child: Icon(Lucide.ImageOff, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)),
        );
      },
    );
  }
}
