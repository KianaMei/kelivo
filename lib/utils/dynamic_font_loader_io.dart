import 'dart:io';
import 'package:flutter/services.dart';

/// Runtime local font loader. Registers a font family alias with the engine.
class DynamicFontLoader {
  static final Set<String> _loaded = <String>{};

  static Future<void> ensureLoaded({required String alias, required String path}) async {
    if (_loaded.contains(alias)) return;
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(alias);
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    _loaded.add(alias);
  }

  static String aliasForPath(String path, {String prefix = 'Local'}) {
    final file = File(path);
    final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'font';
    final base = name.replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), '');
    // Avoid spaces to keep alias simple
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'Kelivo_${prefix}_$sanitized';
  }
}

