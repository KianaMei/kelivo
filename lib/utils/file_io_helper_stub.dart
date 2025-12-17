import 'dart:typed_data';

/// Web stub - file IO not supported
Future<void> writeFile(String path, Uint8List bytes) async {
  throw UnsupportedError('File write not supported on web');
}

/// Web stub - returns null placeholder
dynamic createFile(String path) => null;
