
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
    // Web: No local file access. If path is a network URL (unlikely here), use Image.network.
    // Otherwise show placeholder.
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _error(context),
      );
    }
    return _error(context);
  }

  Widget _error(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
      alignment: Alignment.center,
      child: Icon(Lucide.ImageOff, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)),
    );
  }
}
