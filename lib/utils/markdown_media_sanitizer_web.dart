import 'dart:convert';

import '../core/services/upload/upload_service.dart';

class MarkdownMediaSanitizer {
  static final RegExp _imgRe = RegExp(
    r'!\[[^\]]*\]\((data:image\/[a-zA-Z0-9.+-]+;base64,[a-zA-Z0-9+/=\r\n]+)\)',
    multiLine: true,
  );

  static Future<String> replaceInlineBase64Images(String markdown, {String? accessCode}) async {
    if (!markdown.contains('data:image')) return markdown;

    final matches = _imgRe.allMatches(markdown).toList();
    if (matches.isEmpty) return markdown;

    final sb = StringBuffer();
    int last = 0;
    for (final m in matches) {
      sb.write(markdown.substring(last, m.start));
      final dataUrl = m.group(1)!;

      final uploaded = await _uploadDataUrl(dataUrl, accessCode: accessCode);
      if (uploaded == null) {
        sb.write(markdown.substring(m.start, m.end));
        last = m.end;
        continue;
      }

      final replaced = markdown.substring(m.start, m.end).replaceFirst(dataUrl, uploaded);
      sb.write(replaced);
      last = m.end;
    }
    sb.write(markdown.substring(last));
    return sb.toString();
  }

  static Future<String> inlineLocalImagesToBase64(String markdown) async {
    // Web doesn't have readable local filesystem paths in Markdown; keep as-is.
    return markdown;
  }

  static Future<String?> _uploadDataUrl(String dataUrl, {String? accessCode}) async {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    final meta = dataUrl.substring(0, comma);
    final payload = dataUrl.substring(comma + 1).replaceAll('\n', '');
    if (!meta.contains(';base64')) return null;

    final mime = _mimeOf(dataUrl);
    final ext = _extFromMime(mime);
    final bytes = base64Decode(payload);
    final filename = 'inline.$ext';

    final url = await UploadService.uploadBytes(
      filename: filename,
      bytes: bytes,
      accessCode: accessCode,
    );
    return url;
  }

  static String _mimeOf(String dataUrl) {
    try {
      final start = dataUrl.indexOf(':');
      final semi = dataUrl.indexOf(';');
      if (start >= 0 && semi > start) {
        return dataUrl.substring(start + 1, semi);
      }
    } catch (_) {}
    return 'image/png';
  }

  static String _extFromMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/png':
      default:
        return 'png';
    }
  }
}

