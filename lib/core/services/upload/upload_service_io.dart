import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_client.dart';

class UploadService {
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

    final resp = await simpleDio.post(
      endpoint,
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

  static Future<String> uploadFile({
    required String filePath,
    String endpoint = '/webapi/upload',
    String? accessCode,
  }) async {
    final file = File(filePath);
    final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file';
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });

    final headers = <String, String>{};
    if (accessCode != null && accessCode.trim().isNotEmpty) {
      headers['X-Access-Code'] = accessCode.trim();
    }

    final resp = await simpleDio.post(
      endpoint,
      data: form,
      options: Options(headers: headers),
    );

    final data = resp.data;
    if (data is Map && data['url'] is String) {
      return data['url'] as String;
    }
    if (data is String) {
      // best-effort JSON decode
      try {
        final m = jsonDecode(data);
        if (m is Map && m['url'] is String) return m['url'] as String;
      } catch (_) {}
    }
    throw Exception('Upload failed: invalid response');
  }
}
