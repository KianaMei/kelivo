
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../../../utils/avatar_cache.dart';
import '../network/request_logger.dart';
import 'storage_usage_service.dart';

/// IO implementation of StorageUsageService
class StorageUsageService {
  StorageUsageService._(); // Static utility class

  // Helper getters for private stats classes
  static _MutableStats _createMutableStats() => _MutableStats();
  static String _basenameNoExt(String path) => p.basenameWithoutExtension(path);

  /// Renamed from generateReport to match usage
  static Future<StorageUsageReport> computeReport() async {
    return generateReport();
  }

  /// Generates a comprehensive storage usage report.
  static Future<StorageUsageReport> generateReport() async {
    final root = await AppDirectories.getAppDataDirectory();
    // On Windows/Linux/macOS, we scan the entire app data directory recursively.
    
    // Stats accumulators
    int totalFiles = 0;
    int totalBytes = 0;
    
    final byCat = <StorageUsageCategoryKey, _MutableStats>{
      for (final k in StorageUsageCategoryKey.values) k: _MutableStats(),
    };

    // Prepare subcategory maps
    final avatarsDir = await AppDirectories.getAvatarsDirectory();
    final assistantSubs = <String, _MutableStats>{
      'avatars': _MutableStats(),
    };

    final cacheSubs = <String, _MutableStats>{
      'avatars_cache': _MutableStats(),
      'other_cache': _MutableStats(),
    };

    final chatSubs = <String, _MutableStats>{};

    // Helper to classify file
    void classify(File file, String relativePath) {
      final size = file.lengthSync();
      totalBytes += size;
      totalFiles += 1;

      final parts = p.split(relativePath);
      if (parts.isEmpty) {
        byCat[StorageUsageCategoryKey.other]!.add(size);
        return;
      }

      final topDir = parts.first.toLowerCase();

      switch (topDir) {
        case 'logs':
          byCat[StorageUsageCategoryKey.logs]!.add(size);
          break;
        case 'hive':
          // Hive database files are stored under hive/ directory
          final name = parts.last;
          final lower = name.toLowerCase();
          final isHive = lower.endsWith('.hive') || lower.endsWith('.lock');
          if (isHive) {
            byCat[StorageUsageCategoryKey.chatData]!.add(size);
            final box = _basenameNoExt(name);
            final sub = chatSubs.putIfAbsent(box, () => _MutableStats());
            sub.add(size);
          } else {
            byCat[StorageUsageCategoryKey.chatData]!.add(size);
          }
          break;
        case 'avatars':
          byCat[StorageUsageCategoryKey.assistantData]!.add(size);
          assistantSubs['avatars']!.add(size);
          break;
        case 'images':
          // Inline/generated images are stored under appData/images.
          byCat[StorageUsageCategoryKey.images]!.add(size);
          break;
        case 'files':
          // Uploaded files
          byCat[StorageUsageCategoryKey.files]!.add(size);
          break;
        case 'cache':
          byCat[StorageUsageCategoryKey.cache]!.add(size);
          if (parts.length > 1 && parts[1] == 'avatars') {
            cacheSubs['avatars_cache']!.add(size);
          } else {
            cacheSubs['other_cache']!.add(size);
          }
          break;
        default:
          // Check for root level Hive files
          if (relativePath.contains(p.separator) == false) {
             final lower = relativePath.toLowerCase();
             if (lower.endsWith('.hive') || lower.endsWith('.lock')) {
               byCat[StorageUsageCategoryKey.chatData]!.add(size);
               final box = _basenameNoExt(relativePath);
               final sub = chatSubs.putIfAbsent(box, () => _MutableStats());
               sub.add(size);
               return;
             }
          }
          byCat[StorageUsageCategoryKey.other]!.add(size);
          break;
      }
    }

    if (await root.exists()) {
      try {
        final List<FileSystemEntity> entities = await root.list(recursive: true, followLinks: false).toList();
        for (final entity in entities) {
          if (entity is File) {
            final rel = p.relative(entity.path, from: root.path);
            classify(entity, rel);
          }
        }
      } catch (e) {
        // Ignore access errors
      }
    }

    // Build subcategories lists
    final chatSubList = chatSubs.entries.map((e) => StorageUsageSubcategory(id: e.key, stats: e.value.toStats())).toList();
    // Sort chat subs by size desc
    chatSubList.sort((a, b) => b.stats.bytes.compareTo(a.stats.bytes));

    final categories = <StorageUsageCategory>[
      StorageUsageCategory(key: StorageUsageCategoryKey.images, stats: byCat[StorageUsageCategoryKey.images]!.toStats()),
      StorageUsageCategory(key: StorageUsageCategoryKey.files, stats: byCat[StorageUsageCategoryKey.files]!.toStats()),
      StorageUsageCategory(
        key: StorageUsageCategoryKey.chatData,
        stats: byCat[StorageUsageCategoryKey.chatData]!.toStats(),
        subcategories: chatSubList,
      ),
      StorageUsageCategory(
        key: StorageUsageCategoryKey.assistantData,
        stats: byCat[StorageUsageCategoryKey.assistantData]!.toStats(),
        subcategories: [
          StorageUsageSubcategory(id: 'avatars', stats: assistantSubs['avatars']!.toStats(), path: avatarsDir.path),
        ],
      ),
      StorageUsageCategory(
        key: StorageUsageCategoryKey.cache,
        stats: byCat[StorageUsageCategoryKey.cache]!.toStats(),
        subcategories: [
          StorageUsageSubcategory(id: 'avatars_cache', stats: cacheSubs['avatars_cache']!.toStats()),
          StorageUsageSubcategory(id: 'other_cache', stats: cacheSubs['other_cache']!.toStats()),
        ],
      ),
      StorageUsageCategory(key: StorageUsageCategoryKey.logs, stats: byCat[StorageUsageCategoryKey.logs]!.toStats()),
      StorageUsageCategory(key: StorageUsageCategoryKey.other, stats: byCat[StorageUsageCategoryKey.other]!.toStats()),
    ];

    // Calculate clearable (Cache + Logs)
    final clearable = byCat[StorageUsageCategoryKey.cache]!.toStats() + byCat[StorageUsageCategoryKey.logs]!.toStats();

    return StorageUsageReport(
      totalBytes: totalBytes,
      totalFiles: totalFiles,
      clearable: clearable,
      categories: categories,
    );
  }

  /// Clears cache directory.
  /// If [avatarsOnly] is true, only clears 'cache/avatars'.
  /// Otherwise clears everything in 'cache/'.
  static Future<void> clearCache({bool avatarsOnly = false}) async {
    final cacheDir = await AppDirectories.getCacheDirectory();
    if (!await cacheDir.exists()) return;

    if (avatarsOnly) {
      final avatarCache = Directory(p.join(cacheDir.path, 'avatars'));
      if (await avatarCache.exists()) {
        await _deleteDirectoryContents(avatarCache);
      }
      // Also clear in-memory cache if applicable
      await AvatarCache.clear();
    } else {
      await _deleteDirectoryContents(cacheDir);
      await AvatarCache.clear();
    }
  }

  /// Clears other cache entries (everything except avatars).
  static Future<void> clearOtherCache() async {
     final cacheDir = await AppDirectories.getCacheDirectory();
     if (!await cacheDir.exists()) return;
     
     // Delete all top-level entities except 'avatars' directory
     try {
       await for (final entity in cacheDir.list(recursive: false, followLinks: false)) {
         final name = p.basename(entity.path);
         if (name == 'avatars') continue;
         try {
            if (entity is File) await entity.delete();
            else if (entity is Directory) await entity.delete(recursive: true);
         } catch (_) {}
       }
     } catch (_) {}
  }

  /// Clears logs directory.
  static Future<void> clearLogs() async {
    final dir = await AppDirectories.getAppDataDirectory();
    final logsDir = Directory(p.join(dir.path, 'logs'));
    await _deleteDirectoryContents(logsDir);
  }
  
  /// Clears system temporary cache (platform specific temp dir).
  static Future<void> clearSystemCache() async {
     try {
       // AppDirectories has getSystemCacheDirectory() which usually returns getTemporaryDirectory().
       final sysCache = await AppDirectories.getSystemCacheDirectory();
       await _deleteDirectoryContents(sysCache as Directory);
     } catch (_) {}
  }

  /// Lists all log files with details (path, name, size, modifiedAt).
  static Future<List<StorageFileEntry>> listLogEntries() async {
    final root = await AppDirectories.getAppDataDirectory();
    final logsDir = Directory(p.join(root.path, 'logs'));
     return _listFiles(logsDir);
  }

  /// Deletes specific log files by path.
  static Future<int> deleteLogFiles(Iterable<String> paths) async {
    final root = await AppDirectories.getAppDataDirectory();
    final logsDir = Directory(p.join(root.path, 'logs'));
    return _deleteFiles(paths, logsDir.path);
  }

  /// Lists all assistant avatar files with details (path, name, size, modifiedAt).
  static Future<List<StorageFileEntry>> listAvatarEntries() async {
    final avatarsDir = await AppDirectories.getAvatarsDirectory();
    return _listFiles(avatarsDir, filter: _isImageExt);
  }
  
  /// Lists all uploaded files in files/ directory.
  /// If [images] is true, currently only listing files/ is implemented, logic for separation might be needed if they are stored differently.
  static Future<List<StorageFileEntry>> listUploadEntries({bool images = false}) async {
    final root = await AppDirectories.getAppDataDirectory();
    final filesDir = Directory(p.join(root.path, 'files'));
    // If images=true, maybe filter by extension? Original code implied a separate dir 'images' for inline images,
    // but here the UI passes 'images' flag for uploads too?
    // StorageSpacePage logic: 
    // if key == StorageUsageCategoryKey.images => images=true
    // category.key == images => files stored under 'images'?
    // listUploadEntries is called by _UploadManager.
    // _UploadManager is used for both images and files categories.
    // Let's assume 'uploaded images' vs 'uploaded files'.
    // BUT in generateReport: 
    // case 'images': byCat[StorageUsageCategoryKey.images].add...
    // case 'files': byCat[StorageUsageCategoryKey.files].add...
    // So if images=true, we should list 'images/' directory?
    // But listUploadEntries implementation targetted 'files' directory.
    // Let's check generateReport logic again.
    // 'images' case -> inline/generated images.
    // 'files' case -> uploaded files.
    
    // If user wants to "manage" images, they are in 'images/' dir.
    if (images) {
       final imgDir = Directory(p.join(root.path, 'images'));
       return _listFiles(imgDir);
    }
    return _listFiles(filesDir);
  }

  /// Deletes specific uploaded files.
  static Future<int> deleteUploadFiles(Iterable<String> paths, {bool images = false}) async {
     final root = await AppDirectories.getAppDataDirectory();
     final dirName = images ? 'images' : 'files';
     final dir = Directory(p.join(root.path, dirName));
     return _deleteFiles(paths, dir.path);
  }

  static bool _isImageExt(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.ico');
  }

  /// Deletes specific avatar files by path.
  static Future<int> deleteAvatarFiles(Iterable<String> paths) async {
    final avatarsDir = await AppDirectories.getAvatarsDirectory();
    return _deleteFiles(paths, avatarsDir.path);
  }

  /// Clears all assistant avatars.
  static Future<void> clearAvatars() async {
    final dir = await AppDirectories.getAvatarsDirectory();
    await _deleteDirectoryContents(dir);
  }

  /// Lists all cached avatar files with details (path, name, size, modifiedAt).
  static Future<List<StorageFileEntry>> listCacheEntries() async {
    final cacheDir = await AppDirectories.getCacheDirectory();
    return _listFiles(cacheDir, recursive: true);
  }

  /// Lists all chat data (Hive database) files with details.
  static Future<List<StorageFileEntry>> listChatDataEntries() async {
    final root = await AppDirectories.getAppDataDirectory();
    final out = <StorageFileEntry>[];

    if (!await root.exists()) return out;

    try {
      // Check hive/ subdirectory first
      final hiveDir = Directory(p.join(root.path, 'hive'));
      if (await hiveDir.exists()) {
        await for (final ent in hiveDir.list(recursive: false, followLinks: false)) {
          if (ent is! File) continue;
          final name = p.basename(ent.path);
          final lower = name.toLowerCase();
          if (!lower.endsWith('.hive') && !lower.endsWith('.lock')) continue;
           out.add(await _createEntry(ent));
        }
      }

      // Also check root level for hive files
      await for (final ent in root.list(recursive: false, followLinks: false)) {
        if (ent is! File) continue;
        final name = p.basename(ent.path);
        // Only if regex matches or known hive names? 
        // Logic from original:
        final lower = name.toLowerCase();
        if (!lower.endsWith('.hive') && !lower.endsWith('.lock')) continue;
        out.add(await _createEntry(ent));
      }
    } catch (_) {
      // Ignore listing errors and return partial results.
    }

    // Sort by size, largest first.
    out.sort((a, b) => b.bytes.compareTo(a.bytes));
    return out;
  }
  
  // -- Private Helper Methods --
  
  static Future<StorageFileEntry> _createEntry(File ent) async {
      final name = p.basename(ent.path);
      int bytes = 0;
      DateTime modifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        final stat = await ent.stat();
        bytes = stat.size;
        modifiedAt = stat.modified;
      } catch (_) {
        try {
          bytes = await ent.length();
        } catch (_) {}
      }
      return StorageFileEntry(path: ent.path, name: name, bytes: bytes, modifiedAt: modifiedAt);
  }

  static Future<List<StorageFileEntry>> _listFiles(Directory dir, {bool recursive = true, bool Function(String name)? filter}) async {
    final out = <StorageFileEntry>[];
    if (!await dir.exists()) return out;
    try {
      await for (final ent in dir.list(recursive: recursive, followLinks: false)) {
        if (ent is! File) continue;
        final name = p.basename(ent.path);
        if (filter != null && !filter(name)) continue;
        out.add(await _createEntry(ent));
      }
    } catch (_) {}
    out.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return out;
  }
  
  static Future<int> _deleteFiles(Iterable<String> paths, String rootPath) async {
    final rootAbs = p.normalize(Directory(rootPath).absolute.path);
    int deleted = 0;
    for (final raw in paths) {
      try {
        final abs = p.normalize(File(raw).absolute.path);
        if (!p.isWithin(rootAbs, abs) && abs != rootAbs) continue;
        final f = File(abs);
        if (await f.exists()) {
          await f.delete();
          deleted += 1;
        }
      } catch (_) {}
    }
    return deleted;
  }

  static Future<void> _deleteDirectoryContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        try {
          if (entity is File) {
             await entity.delete();
          } else if (entity is Directory) {
             await entity.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}

class _MutableStats {
  int fileCount = 0;
  int bytes = 0;

  void add(int size) {
    fileCount++;
    bytes += size;
  }

  StorageUsageStats toStats() => StorageUsageStats(fileCount: fileCount, bytes: bytes);
}
