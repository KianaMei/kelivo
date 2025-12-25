import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

/// 平台工具类，提供跨平台兼容性支持
class PlatformUtils {
  /// 检查是否为桌面平台
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 检查是否为移动平台
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if running on Android
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Check if running on iOS
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Check if running on macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// Check if running on Linux
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Check if running on Fuchsia
  static bool get isFuchsia => !kIsWeb && Platform.isFuchsia;

  /// Check if running on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;


  /// 安全地检查文件是否存在
  static bool fileExistsSync(String path) {
    if (kIsWeb) return false;
    try {
      return File(path).existsSync();
    } catch (e) {
      return false;
    }
  }

  /// 安全地检查文件是否存在（异步）
  static Future<bool> fileExists(String path) async {
    if (kIsWeb) return false;
    try {
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }

  /// 安全地读取文件
  static Future<List<int>?> readFileBytes(String path) async {
    if (kIsWeb) return null;
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error reading file: $e');
    }
    return null;
  }

  /// 安全地写入文件
  static Future<bool> writeFileBytes(String path, List<int> bytes) async {
    if (kIsWeb) return false;
    try {
      final file = File(path);
      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('Error writing file: $e');
      return false;
    }
  }

  /// 安全地调用平台特定的插件
  static Future<void> deleteFile(String path) async {
    if (kIsWeb) return;
    final lower = path.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static void deleteFileSync(String path) {
    if (kIsWeb) return;
    final lower = path.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static Future<T?> callPlatformMethod<T>(Future<T> Function() method, {T? fallback}) async {
    try {
      return await method();
    } on MissingPluginException catch (e) {
      debugPrint('Plugin not available: $e');
      return fallback;
    } on PlatformException catch (e) {
      debugPrint('Platform error: $e');
      return fallback;
    } catch (e) {
      debugPrint('Unexpected error: $e');
      return fallback;
    }
  }

  /// 检查插件是否可用
  static Future<bool> isPluginAvailable(Future<void> Function() testMethod) async {
    try {
      await testMethod();
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 获取支持的文件选择器扩展名
  static List<String> getSupportedFileExtensions() {
    if (isWindows) {
      // Windows支持的文件类型
      return ['pdf', 'txt', 'doc', 'docx', 'md', 'json', 'xml', 'csv'];
    }
    // 其他平台
    return ['*'];
  }

  /// 检查是否支持触觉反馈
  static bool get supportsHapticFeedback {
    return isMobile && !kIsWeb;
  }

  /// 检查是否支持文件分享
  static bool get supportsFileSharing {
    return !kIsWeb;
  }

  /// 检查是否支持相机
  static bool get supportsCamera {
    return !kIsWeb;
  }

  /// Get a FileImage provider for the given path (IO only)
  static ImageProvider? fileImageProvider(String path) {
    if (kIsWeb) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return FileImage(file);
    } catch (_) {
      return null;
    }
  }
}
