/// Web version of AppDirs.
///
/// Flutter Web doesn't have direct filesystem access; Hive uses IndexedDB.
/// This file provides a minimal API surface so the rest of the app can compile.
class AppDirs {
  AppDirs._();

  static Future<void> init() async {}

  static Future<_WebDirectory> dataRoot() async => const _WebDirectory('');

  static Future<String> hivePath() async => '';

  static Future<_WebDirectory> ensureSubDir(String relativePath) async => const _WebDirectory('');
}

class _WebDirectory {
  final String path;
  const _WebDirectory(this.path);
}

