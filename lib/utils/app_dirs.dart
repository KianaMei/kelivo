import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized app data directories to avoid cross-build conflicts on Windows.
///
/// Rationale:
/// - Previous code scattered getApplicationDocumentsDirectory() calls, which on
///   Windows resolves to the user's global Documents folder. That causes data
///   clashes between different builds (fork vs upstream) running under the same account.
/// - We switch Windows to use Application Support (AppData/Roaming) under a
///   namespaced subfolder (Kelivo). Other platforms keep Documents for
///   compatibility.
/// - Optional override via env var KELIVO_DATA_DIR for power users.
class AppDirs {
  AppDirs._();

  static Directory? _root;

  /// Initialize and perform best-effort legacy migration on Windows.
  static Future<void> init() async {
    if (kIsWeb) return; // Not applicable
    final root = await dataRoot();
    // Windows-only: migrate from legacy Documents-based layout if applicable.
    if (Platform.isWindows) {
      await _maybeMigrateFromLegacyWindows(root);
    }
  }

  /// Returns the base directory for persistent app data.
  /// - Windows: %APPDATA%/Kelivo
  /// - Others:  getApplicationDocumentsDirectory()
  /// - Env override: KELIVO_DATA_DIR (absolute path)
  static Future<Directory> dataRoot() async {
    if (_root != null) return _root!;
    if (kIsWeb) {
      throw UnsupportedError('AppDirs is not supported on web');
    }

    // Environment override for advanced users/testing
    final override = Platform.environment['KELIVO_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      final dir = Directory(override.trim());
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _root = dir;
      return _root!;
    }

    if (Platform.isWindows) {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'Kelivo'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _root = dir;
      return _root!;
    }

    // Keep legacy behavior for non-Windows platforms
    final docs = await getApplicationDocumentsDirectory();
    if (!await docs.exists()) {
      await docs.create(recursive: true);
    }
    _root = docs;
    return _root!;
  }

  /// Hive storage directory path inside dataRoot.
  static Future<String> hivePath() async {
    final root = await dataRoot();
    final hiveDir = Directory(p.join(root.path, 'hive'));
    if (!await hiveDir.exists()) {
      await hiveDir.create(recursive: true);
    }
    return hiveDir.path;
  }

  /// Ensure and return a subdirectory under dataRoot.
  static Future<Directory> ensureSubDir(String relativePath) async {
    final root = await dataRoot();
    final dir = Directory(p.join(root.path, relativePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _maybeMigrateFromLegacyWindows(Directory newRoot) async {
    try {
      // Legacy root used getApplicationDocumentsDirectory() directly.
      final legacyRoot = await getApplicationDocumentsDirectory();
      // If legacy == new, nothing to do.
      if (p.equals(legacyRoot.path, newRoot.path)) return;

      // Migration heuristic: Only copy if newRoot appears empty and legacy has data.
      final newEntries = await newRoot.list().toList();
      if (newEntries.isNotEmpty) return;

      final candidates = <String>['hive', 'upload', 'avatars', 'images', p.join('cache', 'avatars')];
      bool hasLegacyData = false;
      for (final rel in candidates) {
        final d = Directory(p.join(legacyRoot.path, rel));
        if (await d.exists()) { hasLegacyData = true; break; }
      }
      if (!hasLegacyData) return;

      // Best-effort copy; skip on error to avoid blocking startup.
      for (final rel in candidates) {
        final src = Directory(p.join(legacyRoot.path, rel));
        final dst = Directory(p.join(newRoot.path, rel));
        if (await src.exists() && !await dst.exists()) {
          await _copyDirectory(src, dst);
        }
      }
    } catch (_) {
      // Ignore migration errors silently; never block user startup.
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: src.path);
      final newPath = p.join(dst.path, rel);
      if (entity is File) {
        final newFile = File(newPath);
        await newFile.parent.create(recursive: true);
        await entity.copy(newFile.path);
      } else if (entity is Directory) {
        final newDir = Directory(newPath);
        await newDir.create(recursive: true);
      }
    }
  }
}

