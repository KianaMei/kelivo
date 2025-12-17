import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Web 版运行时字体加载：
/// - 浏览器没有“任意文件路径读取”，所以这里只支持 `data:` URL（base64）形式。
/// - 后续在设置页里把用户上传的字体存成 dataURL，即可保持功能等价。
class DynamicFontLoader {
  static final Set<String> _loaded = <String>{};

  static Future<void> ensureLoaded({required String alias, required String path}) async {
    if (_loaded.contains(alias)) return;
    if (!path.startsWith('data:')) {
      throw UnsupportedError('Web local font requires data: URL');
    }
    final comma = path.indexOf(',');
    if (comma < 0) throw FormatException('Invalid data URL');
    final meta = path.substring(0, comma);
    if (!meta.contains(';base64')) throw FormatException('Font data URL must be base64');
    final b64 = path.substring(comma + 1);
    final bytes = base64Decode(b64);

    final loader = FontLoader(alias);
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
    _loaded.add(alias);
  }

  static String aliasForPath(String path, {String prefix = 'Local'}) {
    // Path is not meaningful on web; keep it deterministic.
    final sanitized = base64Url.encode(utf8.encode(path)).replaceAll('=', '');
    return 'Kelivo_${prefix}_$sanitized';
  }
}

