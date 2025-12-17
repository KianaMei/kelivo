import 'package:dio/dio.dart';

/// Web 端不提供本地文件缓存：直接走 CDN（或由上层通过 nginx/service-worker 缓存）。
class RuntimeCacheService {
  static final RuntimeCacheService _instance = RuntimeCacheService._();
  static RuntimeCacheService get instance => _instance;
  RuntimeCacheService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  bool _isOfflineMode = false;

  static const Map<String, String> _cdnUrls = {
    'react.development.js': 'https://unpkg.com/react@18/umd/react.development.js',
    'react-dom.development.js': 'https://unpkg.com/react-dom@18/umd/react-dom.development.js',
    'babel.min.js': 'https://unpkg.com/@babel/standalone/babel.min.js',
    'vue.global.js': 'https://unpkg.com/vue@3/dist/vue.global.js',
  };

  static const Map<String, String> _libraryNames = {
    'react.development.js': 'React 18',
    'react-dom.development.js': 'ReactDOM 18',
    'babel.min.js': 'Babel',
    'vue.global.js': 'Vue 3',
  };

  bool get isOfflineMode => _isOfflineMode;

  Future<void> init() async {}

  Future<String> getCacheDir() async => '';

  Future<bool> isCached(String fileName) async => false;

  Future<Map<String, bool>> getCacheStatus() async {
    return {for (final k in _cdnUrls.keys) k: false};
  }

  Future<Map<String, bool>> downloadAll({void Function(String fileName, int progress)? onProgress}) async {
    final out = <String, bool>{};
    for (final entry in _cdnUrls.entries) {
      final ok = await download(entry.key);
      out[entry.key] = ok;
      onProgress?.call(entry.key, ok ? 100 : 0);
    }
    return out;
  }

  Future<bool> download(String fileName) async {
    final url = _cdnUrls[fileName];
    if (url == null) return false;
    try {
      await _dio.get<void>(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getLocalPath(String fileName) async => null;

  Future<String> getLibraryUrl(String fileName, {bool preferLocal = true}) async {
    return _cdnUrls[fileName] ?? '';
  }

  void setOfflineMode(bool offline) {
    _isOfflineMode = offline;
  }

  Future<void> clearCache() async {}

  Future<int> getCacheSize() async => 0;

  static String getLibraryName(String fileName) {
    return _libraryNames[fileName] ?? fileName;
  }

  static List<String> get libraryFileNames => _cdnUrls.keys.toList();
}

