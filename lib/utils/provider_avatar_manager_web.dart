import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/services/upload/upload_service.dart';

class ProviderAvatarManager {
  ProviderAvatarManager._();

  static Future<String> saveAvatar(
    String providerId,
    Uint8List imageBytes, {
    String? accessCode,
  }) async {
    img.Image? image;
    try {
      image = img.decodeImage(imageBytes);
      image ??= img.decodeJpg(imageBytes);
      image ??= img.decodePng(imageBytes);
      image ??= img.decodeGif(imageBytes);
      image ??= img.decodeBmp(imageBytes);
      image ??= img.decodeWebP(imageBytes);
    } catch (_) {}
    if (image == null) {
      throw FormatException('Unsupported image format');
    }

    final resized = _resizeImage(image, 512);
    final png = img.encodePng(resized, level: 6);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'provider_${providerId}_$ts.png';
    return UploadService.uploadBytes(
      bytes: Uint8List.fromList(png),
      fileName: fileName,
      contentType: 'image/png',
      accessCode: accessCode,
    );
  }

  static Future<void> deleteAvatar(String providerId, {String? accessCode}) async {}

  static Future<String?> getAvatarPath(String relativePathOrUrl) async {
    if (relativePathOrUrl.isEmpty) return null;
    final trimmed = relativePathOrUrl.trim();
    // If it's already a URL, return it directly
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // If it's a data URL, return it directly
    if (trimmed.startsWith('data:')) {
      return trimmed;
    }
    // For relative paths on web, we can't resolve them without Gateway
    // Return null to fall back to default avatar
    return null;
  }

  static img.Image _resizeImage(img.Image image, int maxSize) {
    if (image.width <= maxSize && image.height <= maxSize) return image;
    final aspectRatio = image.width / image.height;
    int newWidth;
    int newHeight;
    if (aspectRatio > 1) {
      newWidth = maxSize;
      newHeight = (maxSize / aspectRatio).round();
    } else {
      newHeight = maxSize;
      newWidth = (maxSize * aspectRatio).round();
    }
    return img.copyResize(image, width: newWidth, height: newHeight, interpolation: img.Interpolation.cubic);
  }
}

