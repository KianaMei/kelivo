import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/services/http/dio_client.dart';

class AvatarCache {
  AvatarCache._();

  static final Map<String, String?> _memo = <String, String?>{};

  static Future<String?> getPath(String url) async {
    if (url.isEmpty) return null;
    if (_memo.containsKey(url)) return _memo[url];
    try {
      final res = await simpleDio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        final bytes = res.data ?? [];
        final mime = _inferMimeFromUrl(url) ?? 'image/png';
        final b64 = base64Encode(bytes);
        final dataUrl = 'data:$mime;base64,$b64';
        _memo[url] = dataUrl;
        return dataUrl;
      }
    } catch (_) {}
    _memo[url] = null;
    return null;
  }

  static Future<void> evict(String url) async {
    _memo.remove(url);
  }

  static String? _inferMimeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    return 'image/png';
  }
}

