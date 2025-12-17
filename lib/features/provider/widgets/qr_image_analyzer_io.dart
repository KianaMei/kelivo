import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

String _extFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.webp')) return 'webp';
  if (lower.endsWith('.gif')) return 'gif';
  return 'jpg';
}

Future<String?> decodeQrFromImageFile(PlatformFile file) async {
  String? path = file.path;
  File? temp;
  try {
    if ((path == null || path.isEmpty) && file.bytes != null) {
      final tmp = await getTemporaryDirectory();
      final ext = _extFromName(file.name);
      temp = File('${tmp.path}/qr_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await temp.writeAsBytes(file.bytes!);
      path = temp.path;
    }
    if (path == null || path.isEmpty) return null;

    final scanner = MobileScannerController();
    final result = await scanner.analyzeImage(path);
    String? code;
    if (result != null) {
      try {
        final bars = (result as dynamic).barcodes as List?;
        if (bars != null) {
          for (final b in bars) {
            final v = (b as dynamic).rawValue as String?;
            if (v != null && v.isNotEmpty) {
              code = v;
              break;
            }
          }
        }
      } catch (_) {}
    }
    return code;
  } finally {
    try {
      await temp?.delete();
    } catch (_) {}
  }
}

