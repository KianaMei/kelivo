import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/app_dirs.dart';

Future<List<String>> persistClipboardImages(List<String> srcPaths) async {
  try {
    final root = await AppDirs.dataRoot();
    final dir = Directory(p.join(root.path, 'upload'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final out = <String>[];
    var i = 0;
    for (final raw in srcPaths) {
      try {
        final src = raw.startsWith('file://') ? raw.substring(7) : raw;
        if (src.contains('/Documents/upload/')) {
          out.add(src);
          continue;
        }
        final ext = p.extension(src).isNotEmpty ? p.extension(src) : '.png';
        final name = 'paste_${DateTime.now().millisecondsSinceEpoch}_${i++}$ext';
        final destPath = p.join(dir.path, name);
        final from = File(src);
        if (await from.exists()) {
          await File(destPath).writeAsBytes(await from.readAsBytes());
          try {
            await from.delete();
          } catch (_) {}
          out.add(destPath);
        }
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

