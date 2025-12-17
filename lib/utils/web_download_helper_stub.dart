import 'dart:typed_data';

/// Stub for non-web platforms - should not be called
void downloadBytes(Uint8List bytes, String filename) {
  throw UnsupportedError('downloadBytes is only supported on web');
}
