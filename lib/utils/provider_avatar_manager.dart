import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;

/// Manages provider custom avatars: compression, storage, and deletion.
class ProviderAvatarManager {
  ProviderAvatarManager._();

  static Future<Directory> _avatarDir() async {
    // New canonical location: Documents/avatars/providers
    // We purposely avoid using a cache/ path because these are user-provided assets
    // that must be backed up and restored across devices.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/avatars/providers');
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
  /// Returns: Relative path for cross-platform compatibility (e.g., 'avatars/providers/xxx_timestamp.png')
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

    // Save to file with timestamp to ensure unique path (triggers ValueKey rebuild in UI)
    final dir = await _avatarDir();
    final safeName = _safeFileName(providerId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = '${safeName}_$timestamp.png';
    final file = File('${dir.path}/$filename');

    // Delete old avatars for this provider to avoid clutter
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains(safeName) && entity.path != file.path) {
          await entity.delete();
        }
      }
    } catch (_) {}

    await file.writeAsBytes(png, flush: true);

    // Return relative path for cross-platform compatibility (now under avatars/)
    return 'avatars/providers/$filename';
  }

  /// Deletes the custom avatar(s) for a provider.
  /// Since avatars now include timestamps, this deletes all matching files.
  static Future<void> deleteAvatar(String providerId) async {
    if (kIsWeb) return;

    try {
      final safeName = _safeFileName(providerId);
      // New location
      final dir = await _avatarDir();
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains(safeName)) {
          await entity.delete();
        }
      }
      // Legacy location cleanup (best effort)
      try {
        final docs = await getApplicationDocumentsDirectory();
        final legacyDir = Directory('${docs.path}/cache/avatars/providers');
        if (await legacyDir.exists()) {
          await for (final entity in legacyDir.list()) {
            if (entity is File && entity.path.contains(safeName)) {
              await entity.delete();
            }
          }
        }
      } catch (_) {}
    } catch (_) {
      // Ignore errors during deletion
    }
  }

  /// Gets the relative file path for a provider's custom avatar if it exists.
  /// Returns the most recent avatar file (by filename timestamp).
  /// Returns: Relative path like 'avatars/providers/xxx_timestamp.png' or null if not found
  static Future<String?> getAvatarPath(String providerId) async {
    if (kIsWeb) return null;

    try {
      final safeName = _safeFileName(providerId);

      // Search in new location first
      final newDir = await _avatarDir();
      final matches = <File>[];
      await for (final entity in newDir.list()) {
        if (entity is File && entity.path.contains(safeName)) {
          matches.add(entity);
        }
      }

      if (matches.isNotEmpty) {
        matches.sort((a, b) => b.path.compareTo(a.path));
        final mostRecent = matches.first;
        final filename = mostRecent.path.split(Platform.pathSeparator).last;
        return 'avatars/providers/$filename';
      }

      // Fallback: look in legacy cache location and migrate the most recent file
      try {
        final docs = await getApplicationDocumentsDirectory();
        final legacyDir = Directory('${docs.path}/cache/avatars/providers');
        if (await legacyDir.exists()) {
          final legacyMatches = <File>[];
          await for (final entity in legacyDir.list()) {
            if (entity is File && entity.path.contains(safeName)) {
              legacyMatches.add(entity);
            }
          }
          if (legacyMatches.isNotEmpty) {
            legacyMatches.sort((a, b) => b.path.compareTo(a.path));
            final mostRecent = legacyMatches.first;
            // Migrate to new location
            final newFilename = mostRecent.path.split(Platform.pathSeparator).last;
            final dest = File('${newDir.path}/$newFilename');
            if (!await dest.exists()) {
              await mostRecent.copy(dest.path);
            }
            return 'avatars/providers/$newFilename';
          }
        }
      } catch (_) {}

      return null;
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
