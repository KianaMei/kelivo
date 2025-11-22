import 'dart:io';
import 'app_dirs.dart';

/// Resolves persisted absolute file paths to the current app data directory.
///
/// Handles multiple scenarios:
/// 1. iOS sandbox UUID changes after app update:
///    Before: /var/mobile/Containers/Data/Application/ABC/Documents/upload/x.png
///    After:  /var/mobile/Containers/Data/Application/XYZ/Documents/upload/x.png
///
/// 2. Cross-platform sync (Windows → Android/iOS):
///    Windows: C:\Users\...\AppData\Roaming\com.ze\kelivo\Kelivo\upload\x.jpg
///    Android: /data/user/0/com.ze.kelivo/app_flutter/upload/x.jpg
///
/// We store absolute paths in message content. This helper rewrites paths
/// to point to the current app data directory. If the rewritten file exists,
/// it returns the new path; otherwise returns the mapped path anyway.
class SandboxPathResolver {
  SandboxPathResolver._();

  static String? _dataRoot;

  /// Call once during app startup to cache the current app data root directory.
  static Future<void> init() async {
    try {
      final dir = await AppDirs.dataRoot();
      _dataRoot = dir.path;
    } catch (_) {
      // Leave null; fix() will no-op in this case.
      _dataRoot = null;
    }
  }

  /// Synchronously map an old absolute path to the current app data directory.
  /// Handles both iOS sandbox changes and cross-platform sync scenarios.
  /// If mapping succeeds and the target exists, returns the mapped path;
  /// otherwise returns the mapped path anyway (file might be created later).
  static String fix(String path) {
    if (path.isEmpty) return path;

    // Strip file:// scheme if present
    final String raw = path.startsWith('file://') ? path.substring(7) : path;

    final root = _dataRoot;
    if (root == null || root.isEmpty) return raw;

    // Normalize path separators to forward slashes for consistent matching
    final normalized = raw.replaceAll('\\', '/');

    // Try to extract relative path from known app-internal folders
    // Pattern 1: iOS/Android style with /Documents/ prefix
    // e.g., /var/mobile/.../Documents/upload/file.jpg
    const unixCandidates = ['/Documents/upload/', '/Documents/avatars/', '/Documents/images/'];
    for (final candidate in unixCandidates) {
      final idx = normalized.indexOf(candidate);
      if (idx != -1) {
        final tail = normalized.substring(idx + '/Documents'.length); // includes the slash
        final mapped = '$root$tail';
        try {
          if (File(mapped).existsSync()) {
            return mapped;
          }
        } catch (_) {}
        // File doesn't exist but path pattern matched, return mapped path anyway
        return mapped;
      }
    }

    // Pattern 2: Direct folder match (works for both Windows and Unix paths)
    // e.g., C:\Users\...\Kelivo\upload\file.jpg → /data/.../upload/file.jpg
    // or: /some/old/path/upload/file.jpg → /current/path/upload/file.jpg
    const folderCandidates = ['/upload/', '/avatars/', '/images/'];
    for (final candidate in folderCandidates) {
      final idx = normalized.lastIndexOf(candidate);
      if (idx != -1) {
        // Extract from folder onwards (e.g., /upload/file.jpg)
        final tail = normalized.substring(idx);
        final mapped = '$root$tail';
        try {
          if (File(mapped).existsSync()) {
            return mapped;
          }
        } catch (_) {}
        // File doesn't exist but path pattern matched, return mapped path anyway
        return mapped;
      }
    }

    return raw;
  }
}
