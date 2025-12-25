import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

/// Web 平台的 PlatformUtils 实现：不提供文件系统/进程能力。
class PlatformUtils {
  static bool get isDesktop => false;
  static bool get isMobile => false;
  
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
  static bool get isWindows => false;

  static bool fileExistsSync(String path) => false;
  static Future<bool> fileExists(String path) async => false;
  static Future<List<int>?> readFileBytes(String path) async => null;
  static Future<bool> writeFileBytes(String path, List<int> bytes) async => false;
  static Future<void> deleteFile(String path) async {}
  static void deleteFileSync(String path) {}

  static Future<T?> callPlatformMethod<T>(Future<T> Function() method, {T? fallback}) async {
    try {
      return await method();
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<bool> isPluginAvailable(Future<void> Function() testMethod) async {
    try {
      await testMethod();
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<String> getSupportedFileExtensions() => const ['*'];

  static bool get supportsHapticFeedback => false;
  static bool get supportsFileSharing => false;
  static bool get supportsCamera => true;

  /// Get a FileImage provider for the given path (not supported on Web)
  static ImageProvider? fileImageProvider(String path) => null;
}
