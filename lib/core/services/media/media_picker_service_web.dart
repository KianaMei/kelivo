import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../upload/upload_service.dart';

/// Web 版媒体选择：
/// - 选择后直接上传到后端，返回 URL（前端只存 URL）
class MediaPickerService {
  static Future<List<String>> copyPickedFiles(List<XFile> files, {String? accessCode}) async {
    final out = <String>[];
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        final name = f.name.isNotEmpty ? f.name : 'file';
        final url = await UploadService.uploadBytes(
          filename: name,
          bytes: bytes,
          accessCode: accessCode,
        );
        out.add(url);
      } catch (_) {}
    }
    return out;
  }

  static String inferMimeByExtension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    return 'text/plain';
  }

  static Future<List<XFile>> pickImages() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return [];

      final out = <XFile>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = f.name.isNotEmpty ? f.name : 'image.png';
        out.add(XFile.fromData(Uint8List.fromList(bytes), name: name));
      }
      return out;
    } catch (e) {
      debugPrint('Error picking images on web: $e');
      return [];
    }
  }

  static Future<List<({String path, String name, String mime})>> pickDocuments({String? accessCode}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'json', 'js', 'pdf', 'docx'],
      );
      if (res == null || res.files.isEmpty) return [];

      final result = <({String path, String name, String mime})>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = f.name.isNotEmpty ? f.name : 'file';
        final mime = inferMimeByExtension(name);
        final url = await UploadService.uploadBytes(
          filename: name,
          bytes: bytes,
          accessCode: accessCode,
        );
        result.add((path: url, name: name, mime: mime));
      }
      return result;
    } catch (e) {
      debugPrint('Error picking files on web: $e');
      return [];
    }
  }
}

