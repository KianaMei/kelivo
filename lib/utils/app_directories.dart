

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'app_dirs.dart';

/// Platform-specific application data directory utilities.
///
/// This is an adapter that integrates with kelivo's AppDirs while providing
/// the same interface as upstream for compatibility.
///
/// - Windows/macOS/Linux: use the Application Support (app data) directory
///   provided by `path_provider`.
/// - Android/iOS: keep using the Application Documents directory.
class AppDirectories {
  AppDirectories._();

  /// Gets the root directory for application data storage.
  ///
  /// Uses kelivo's AppDirs for consistency.
  static Future<dynamic> getAppDataDirectory() async {
    // Use kelivo's unified data root
    return await AppDirs.dataRoot();
  }

  /// Gets the directory for uploaded files.
  static Future<dynamic> getUploadDirectory() async {
    return await AppDirs.ensureSubDir('upload');
  }

  /// Gets the directory for image files.
  static Future<dynamic> getImagesDirectory() async {
    return await AppDirs.ensureSubDir('images');
  }

  /// Gets the directory for avatar files.
  static Future<dynamic> getAvatarsDirectory() async {
    return await AppDirs.ensureSubDir('avatars');
  }

  /// Gets the directory for cache files.
  static Future<dynamic> getCacheDirectory() async {
    return await AppDirs.ensureSubDir('cache');
  }

  /// Gets the platform-provided application cache directory.
  ///
  /// - Android: `/data/user/0/<package>/cache`
  /// - iOS/macOS: Caches directory
  /// - Windows/Linux: platform cache directory (app-specific on Linux via XDG)
  static Future<dynamic> getSystemCacheDirectory() async {
    return await getApplicationCacheDirectory();
  }

  /// Gets the directory for avatar cache files.
  static Future<dynamic> getAvatarCacheDirectory() async {
    return await AppDirs.ensureSubDir(p.join('cache', 'avatars'));
  }
}
