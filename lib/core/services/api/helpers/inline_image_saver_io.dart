import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Utility for saving inline images from API responses.
class InlineImageSaver {
  InlineImageSaver._();

  /// Save a base64-encoded image to the images directory.
  /// Returns the file path on success, null on failure.
  /// [mimeType] is the MIME type (e.g., 'image/png', 'image/jpeg').
  /// [base64Data] is the base64-encoded image data.
  static Future<String?> saveToFile(String mimeType, String base64Data) async {
    try {
      // Import dynamically to avoid import issues
      final appDirs = await _getImagesDirectory();
      if (appDirs == null) return null;

      // Clean up base64 data (remove whitespace)
      final cleanData = base64Data.replaceAll(RegExp(r'\s'), '');
      if (cleanData.isEmpty) return null;

      // Decode base64
      final bytes = base64Decode(cleanData);

      // Determine file extension from MIME type
      String ext = 'png';
      if (mimeType.contains('jpeg') || mimeType.contains('jpg')) {
        ext = 'jpg';
      } else if (mimeType.contains('gif')) {
        ext = 'gif';
      } else if (mimeType.contains('webp')) {
        ext = 'webp';
      }

      // Generate unique filename
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final fileName = 'img_$timestamp.$ext';
      final filePath = '${appDirs.path}/$fileName';

      // Write to file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return filePath;
    } catch (e) {
      // Silently fail, return null
      return null;
    }
  }

  static Future<Directory?> _getImagesDirectory() async {
    try {
      // Use dynamic import to get AppDirectories
      final dir = await _getAppDirsImages();
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _getAppDirsImages() async {
    // Inline implementation to avoid circular imports
    final dataRoot = await _getDataRoot();
    final subDir = Directory('${dataRoot.path}/images');
    if (!await subDir.exists()) {
      await subDir.create(recursive: true);
    }
    return subDir;
  }

  static Future<Directory> _getDataRoot() async {
    // Platform-aware data root implementation
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return dir;
    } else {
      final dir = await getApplicationSupportDirectory();
      return dir;
    }
  }
}
