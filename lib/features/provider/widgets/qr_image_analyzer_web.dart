import 'package:file_picker/file_picker.dart';

Future<String?> decodeQrFromImageFile(PlatformFile file) async {
  // Web 端没有稳定的本地文件路径给 mobile_scanner.analyzeImage 使用，先禁用“相册识别 QR”。
  return null;
}

