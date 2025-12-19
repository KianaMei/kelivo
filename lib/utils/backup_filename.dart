import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

String kelivoPlatformTag() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

String kelivoBackupFileName({DateTime? now, String? platformTag}) {
  final platform = (platformTag ?? kelivoPlatformTag()).trim();
  final ts = (now ?? DateTime.now()).toIso8601String().replaceAll(':', '-');
  return 'kelivo_backup_${platform}_$ts.zip';
}

String kelivoBackupFileNameEpoch({DateTime? now, String? platformTag}) {
  final platform = (platformTag ?? kelivoPlatformTag()).trim();
  final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return 'kelivo_backup_${platform}_$ms.zip';
}

DateTime? tryParseKelivoBackupTimestamp(String fileName) {
  final name = fileName.trim();
  final m = RegExp(r'^kelivo_backup_(?:[a-z0-9]+_)?(.+)\.zip$', caseSensitive: false).firstMatch(name);
  if (m == null) return null;
  final payload = m.group(1) ?? '';
  if (payload.isEmpty) return null;

  final epoch = int.tryParse(payload);
  if (epoch != null) {
    if (epoch >= 1000000000000) return DateTime.fromMillisecondsSinceEpoch(epoch);
    if (epoch >= 1000000000) return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  }

  final normalized = payload.replaceAll(RegExp(r'T(\d{2})-(\d{2})-(\d{2})'), 'T\$1:\$2:\$3');
  return DateTime.tryParse(normalized);
}
