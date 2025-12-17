import 'dart:convert';
import 'dart:html' as html;

import 'package:dio/dio.dart';

import '../http/dio_client.dart';

class UploadService {
  /// Get the Gateway base URL for web.
  /// In development (localhost), uses port 8080.
  /// In production, assumes Gateway is on the same origin.
  static String get gatewayBaseUrl {
    final location = html.window.location;
    final host = location.hostname ?? 'localhost';

    // Development: Flutter runs on different port than Gateway
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://$host:8080';
    }

    // Production: Gateway on same origin
    return location.origin;
  }

  static Future<String> uploadFile({
    required String filePath,
    String endpoint = '/webapi/upload',
    String? accessCode,
  }) async {
    throw UnsupportedError('Web uploadFile is not supported; use uploadBytes');
  }

  static Future<String> uploadBytes({
    required List<int> bytes,
    String? filename,
    String? fileName, // alias for filename
    String endpoint = '/webapi/upload',
    String? accessCode,
    String? contentType,
  }) async {
    final effectiveFilename = filename ?? fileName ?? 'file';
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: effectiveFilename,
        contentType: contentType != null ? DioMediaType.parse(contentType) : null,
      ),
    });

    final headers = <String, String>{};
    if (accessCode != null && accessCode.trim().isNotEmpty) {
      headers['X-Access-Code'] = accessCode.trim();
    }

    // Use full Gateway URL instead of relative path
    final fullUrl = '$gatewayBaseUrl$endpoint';

    final resp = await simpleDio.post(
      fullUrl,
      data: form,
      options: Options(headers: headers),
    );

    final data = resp.data;
    if (data is Map && data['url'] is String) {
      return data['url'] as String;
    }
    if (data is String) {
      try {
        final m = jsonDecode(data);
        if (m is Map && m['url'] is String) return m['url'] as String;
      } catch (_) {}
    }
    throw Exception('Upload failed: invalid response');
  }
}
