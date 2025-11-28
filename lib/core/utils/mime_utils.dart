/// MIME type utilities for file extension and data URL handling.
///
/// This module provides centralized MIME type resolution to avoid scattered
/// if/else logic across the codebase. All mappings are extracted from existing
/// implementations to maintain backward compatibility.
class MimeUtils {
  MimeUtils._();

  /// Returns the MIME type for a given file path based on its extension.
  ///
  /// Supports common image formats (jpg, jpeg, png, webp, gif).
  /// Returns `application/octet-stream` for unknown extensions.
  ///
  /// Example:
  /// ```dart
  /// MimeUtils.fromExtension('photo.jpg') // => 'image/jpeg'
  /// MimeUtils.fromExtension('unknown.xyz') // => 'application/octet-stream'
  /// ```
  static String fromExtension(String path) {
    final lower = path.toLowerCase();
    
    // Image formats
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.tiff') || lower.endsWith('.tif')) return 'image/tiff';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    
    // Default fallback
    return 'application/octet-stream';
  }

  /// Extracts the MIME type from a data URL.
  ///
  /// Parses data URLs in the format: `data:<mime>;base64,<data>`
  /// Returns `image/png` as fallback if parsing fails.
  ///
  /// Example:
  /// ```dart
  /// MimeUtils.fromDataUrl('data:image/jpeg;base64,/9j/4AA...') // => 'image/jpeg'
  /// MimeUtils.fromDataUrl('invalid') // => 'image/png'
  /// ```
  static String fromDataUrl(String dataUrl) {
    try {
      final colon = dataUrl.indexOf(':');
      final semi = dataUrl.indexOf(';');
      if (colon >= 0 && semi > colon) {
        return dataUrl.substring(colon + 1, semi);
      }
    } catch (_) {
      // Parsing failed, return fallback
    }
    return 'image/png';
  }

  /// Checks if a MIME type represents an image.
  ///
  /// Returns `true` for any MIME type starting with `image/`.
  ///
  /// Example:
  /// ```dart
  /// MimeUtils.isImage('image/png') // => true
  /// MimeUtils.isImage('text/plain') // => false
  /// ```
  static bool isImage(String mime) {
    return mime.toLowerCase().startsWith('image/');
  }

  /// Checks if a MIME type represents text content.
  ///
  /// Returns `true` for MIME types starting with `text/` or common text formats.
  ///
  /// Example:
  /// ```dart
  /// MimeUtils.isText('text/plain') // => true
  /// MimeUtils.isText('application/json') // => true
  /// MimeUtils.isText('image/png') // => false
  /// ```
  static bool isText(String mime) {
    final lower = mime.toLowerCase();
    return lower.startsWith('text/') ||
        lower == 'application/json' ||
        lower == 'application/xml' ||
        lower == 'application/javascript';
  }

  /// Infers if a file path or URL represents an image based on extension.
  ///
  /// This is a convenience method that checks common image extensions.
  /// More reliable than MIME type checking when dealing with URLs.
  ///
  /// Example:
  /// ```dart
  /// MimeUtils.isImagePath('photo.jpg') // => true
  /// MimeUtils.isImagePath('https://example.com/image.png') // => true
  /// MimeUtils.isImagePath('document.pdf') // => false
  /// ```
  static bool isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.contains(RegExp(r'\.(png|jpg|jpeg|gif|webp|bmp|svg|tiff|tif|ico|heic|heif)(\?|$)'));
  }
}
