import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/app_dirs.dart';

/// 媒体选择服务 - 处理文件选择和复制
class MediaPickerService {
  /// 复制选择的文件到应用数据目录
  ///
  /// [files] - XFile 列表
  /// 返回保存后的文件路径列表
  static Future<List<String>> copyPickedFiles(List<XFile> files) async {
    try {
      final docs = await PlatformUtils.callPlatformMethod(
        () => AppDirs.dataRoot(),
        fallback: null,
      );

      if (docs == null) {
        debugPrint('Cannot get documents directory');
        return [];
      }

      final dir = Directory("${docs.path}/upload");
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final out = <String>[];
      for (final f in files) {
        try {
          final name = f.name.isNotEmpty
              ? f.name
              : DateTime.now().millisecondsSinceEpoch.toString();
          final dest = File("${dir.path}/$name");
          await dest.writeAsBytes(await f.readAsBytes());
          out.add(dest.path);
        } catch (_) {}
      }
      return out;
    } catch (e) {
      debugPrint('Error copying files: $e');
      return [];
    }
  }

  /// 根据文件扩展名推断 MIME 类型
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

  /// 选择图片文件
  ///
  /// 返回选择的 XFile 列表，如果取消或失败返回空列表
  static Future<List<XFile>> pickImages() async {
    try {
      final res = await PlatformUtils.callPlatformMethod<FilePickerResult?>(
        () => FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.image,
          withData: false,
        ),
      );
      if (res == null || res.files.isEmpty) return [];
      return res.files
          .where((f) => (f.path ?? '').isNotEmpty)
          .map((f) => XFile(f.path!))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Error picking images with FilePicker: $e');
      return [];
    }
  }

  /// 选择文档文件
  ///
  /// 返回 (保存路径, 原始文件名, MIME类型) 的列表
  static Future<List<({String path, String name, String mime})>> pickDocuments() async {
    try {
      // Get supported extensions based on platform
      final extensions = PlatformUtils.isWindows
          ? PlatformUtils.getSupportedFileExtensions()
          : ['txt', 'md', 'json', 'js', 'pdf', 'docx'];

      final res = await PlatformUtils.callPlatformMethod<FilePickerResult?>(
        () => FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: false,
          type: FileType.custom,
          allowedExtensions: extensions,
        ),
      );

      if (res == null || res.files.isEmpty) return [];

      final toCopy = <XFile>[];
      for (final f in res.files) {
        if (f.path != null && f.path!.isNotEmpty) {
          toCopy.add(XFile(f.path!));
        }
      }

      final saved = await copyPickedFiles(toCopy);
      final result = <({String path, String name, String mime})>[];

      for (int i = 0; i < saved.length; i++) {
        final orig = res.files[i];
        final savedPath = saved[i];
        final name = orig.name;
        final mime = inferMimeByExtension(name);
        result.add((path: savedPath, name: name, mime: mime));
      }

      return result;
    } catch (e) {
      debugPrint('Error picking files: $e');
      return [];
    }
  }
}
