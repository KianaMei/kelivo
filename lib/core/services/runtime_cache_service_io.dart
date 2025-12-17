// IO implementation (mobile/desktop)
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

/// Service to cache frontend runtime libraries locally
/// Downloads CDN resources to local cache for offline support
class RuntimeCacheService {
  static final RuntimeCacheService _instance = RuntimeCacheService._();
  static RuntimeCacheService get instance => _instance;
  RuntimeCacheService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String? _cacheDir;
  bool _isInitialized = false;
  bool _isOfflineMode = false;

  /// CDN URLs for runtime libraries
  static const Map<String, String> _cdnUrls = {
    'react.development.js': 'https://unpkg.com/react@18/umd/react.development.js',
    'react-dom.development.js': 'https://unpkg.com/react-dom@18/umd/react-dom.development.js',
    'babel.min.js': 'https://unpkg.com/@babel/standalone/babel.min.js',
    'vue.global.js': 'https://unpkg.com/vue@3/dist/vue.global.js',
    // Tailwind CSS is loaded from CDN only (too dynamic to cache)
  };

  /// Library display names for UI
  static const Map<String, String> _libraryNames = {
    'react.development.js': 'React 18',
    'react-dom.development.js': 'ReactDOM 18',
    'babel.min.js': 'Babel',
    'vue.global.js': 'Vue 3',
  };

  /// Whether offline mode is enabled
  bool get isOfflineMode => _isOfflineMode;

  /// Initialize the cache directory
  Future<void> init() async {
    if (_isInitialized) return;

    final appDir = await getApplicationSupportDirectory();
    _cacheDir = '${appDir.path}${Platform.pathSeparator}runtime_cache';
    
    final dir = Directory(_cacheDir!);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    
    _isInitialized = true;
  }

  /// Get the cache directory path
  Future<String> getCacheDir() async {
    await init();
    return _cacheDir!;
  }

  /// Check if a library is cached locally
  Future<bool> isCached(String fileName) async {
    await init();
    final file = File('$_cacheDir${Platform.pathSeparator}$fileName');
    return file.existsSync();
  }

  /// Get all cached libraries status
  Future<Map<String, bool>> getCacheStatus() async {
    await init();
    final status = <String, bool>{};
    for (final fileName in _cdnUrls.keys) {
      status[fileName] = await isCached(fileName);
    }
    return status;
  }

  /// Download all runtime libraries to cache
  /// Returns a map of fileName -> success status
  Future<Map<String, bool>> downloadAll({
    void Function(String fileName, int progress)? onProgress,
  }) async {
    await init();
    final results = <String, bool>{};

    for (final entry in _cdnUrls.entries) {
      final fileName = entry.key;
      final url = entry.value;
      
      try {
        final file = File('$_cacheDir${Platform.pathSeparator}$fileName');
        
        await _dio.download(
          url,
          file.path,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = (received / total * 100).round();
              onProgress?.call(fileName, progress);
            }
          },
        );
        
        results[fileName] = true;
      } catch (e) {
        results[fileName] = false;
      }
    }

    return results;
  }

  /// Download a single library
  Future<bool> download(String fileName) async {
    await init();
    final url = _cdnUrls[fileName];
    if (url == null) return false;

    try {
      final file = File('$_cacheDir${Platform.pathSeparator}$fileName');
      await _dio.download(url, file.path);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get the local file path for a library
  Future<String?> getLocalPath(String fileName) async {
    await init();
    final file = File('$_cacheDir${Platform.pathSeparator}$fileName');
    if (file.existsSync()) {
      return file.path;
    }
    return null;
  }

  /// Get the URL to use for a library (local file:// or CDN https://)
  /// Prefers local cache if available
  Future<String> getLibraryUrl(String fileName, {bool preferLocal = true}) async {
    if (preferLocal || _isOfflineMode) {
      final localPath = await getLocalPath(fileName);
      if (localPath != null) {
        // Convert to file:// URL
        return Uri.file(localPath).toString();
      }
    }
    
    // Fall back to CDN
    return _cdnUrls[fileName] ?? '';
  }

  /// Set offline mode (use only local cache)
  void setOfflineMode(bool offline) {
    _isOfflineMode = offline;
  }

  /// Clear all cached libraries
  Future<void> clearCache() async {
    await init();
    final dir = Directory(_cacheDir!);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  /// Get total cache size in bytes
  Future<int> getCacheSize() async {
    await init();
    final dir = Directory(_cacheDir!);
    if (!dir.existsSync()) return 0;

    int size = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  /// Get library display name
  static String getLibraryName(String fileName) {
    return _libraryNames[fileName] ?? fileName;
  }

  /// Get all library file names
  static List<String> get libraryFileNames => _cdnUrls.keys.toList();
}
