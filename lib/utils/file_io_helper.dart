import 'dart:io';
import 'dart:typed_data';

/// Write bytes to file (IO platforms only)
Future<void> writeFile(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

/// Read file as File object for CherryImporter (IO platforms only)
File createFile(String path) => File(path);
