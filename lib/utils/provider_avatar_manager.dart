import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;

/// Manages provider custom avatars: compression, storage, and deletion.
class ProviderAvatarManager {
  ProviderAvatarManager._();

  static Future<Directory> _avatarDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/cache/avatars/providers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves an avatar for a provider with lossless PNG compression.
  ///
  /// [providerId]: Unique identifier for the provider
  /// [imageBytes]: Raw image bytes (can be from file or network)
  ///
  /// Returns: Relative path for cross-platform compatibility (e.g., 'cache/avatars/providers/xxx.png')
  static Future<String> saveAvatar(String providerId, Uint8List imageBytes) async {
    if (kIsWeb) {
      throw UnsupportedError('Custom avatars not supported on web');
    }

    // Decode image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw FormatException('Invalid image format');
    }

    // Resize to max 512x512 (maintain aspect ratio)
    final resized = _resizeImage(image, 512);

    // Encode as PNG (lossless)
    final png = img.encodePng(resized, level: 6); // level 6 = good compression without being too slow

    // Save to file
    final dir = await _avatarDir();
    final safeName = _safeFileName(providerId);
    final file = File('${dir.path}/$safeName.png');

    // Delete old file first to avoid cache issues
    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(png, flush: true);

    // Return relative path for cross-platform compatibility
    return 'cache/avatars/providers/$safeName.png';
  }

  /// Deletes the custom avatar for a provider.
  static Future<void> deleteAvatar(String providerId) async {
    if (kIsWeb) return;

    try {
      final dir = await _avatarDir();
      final safeName = _safeFileName(providerId);
      final file = File('${dir.path}/$safeName.png');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore errors during deletion
    }
  }

  /// Gets the relative file path for a provider's custom avatar if it exists.
  /// Returns: Relative path like 'cache/avatars/providers/xxx.png' or null if not found
  static Future<String?> getAvatarPath(String providerId) async {
    if (kIsWeb) return null;

    try {
      final dir = await _avatarDir();
      final safeName = _safeFileName(providerId);
      final file = File('${dir.path}/$safeName.png');
      if (await file.exists()) {
        return 'cache/avatars/providers/$safeName.png';
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }

  static String _safeFileName(String providerId) {
    // Replace any non-alphanumeric characters with underscores
    return providerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static img.Image _resizeImage(img.Image image, int maxSize) {
    if (image.width <= maxSize && image.height <= maxSize) {
      return image;
    }

    final aspectRatio = image.width / image.height;
    int newWidth, newHeight;

    if (image.width > image.height) {
      newWidth = maxSize;
      newHeight = (maxSize / aspectRatio).round();
    } else {
      newHeight = maxSize;
      newWidth = (maxSize * aspectRatio).round();
    }

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );
  }
}
