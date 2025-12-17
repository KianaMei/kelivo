import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../services/http/dio_client.dart';

class DocumentTextExtractor {
  static Future<String> extract({required String path, required String mime}) async {
    try {
      final bytes = await _loadBytes(path);
      if (bytes == null || bytes.isEmpty) return '[[Failed to read file: empty]]';

      if (mime == 'application/pdf') {
        return '[[PDF text extraction is not supported on web]]';
      }
      if (mime == 'application/msword') {
        return '[[DOC format (.doc) not supported for text extraction]]';
      }
      if (mime == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
        return _extractDocxFromBytes(bytes);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return '[[Failed to read file: $e]]';
    }
  }

  static Future<Uint8List?> _loadBytes(String src) async {
    final s = src.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('data:')) {
      final i = s.indexOf('base64,');
      if (i == -1) return null;
      return Uint8List.fromList(base64Decode(s.substring(i + 7)));
    }
    final lower = s.toLowerCase();
    final isUrl = lower.startsWith('http://') || lower.startsWith('https://');
    if (!isUrl) return null;
    final resp = await simpleDio.get<List<int>>(
      s,
      options: Options(responseType: ResponseType.bytes, validateStatus: (code) => true),
    );
    if (resp.statusCode == null || resp.statusCode! < 200 || resp.statusCode! >= 300) return null;
    final data = resp.data ?? const <int>[];
    return Uint8List.fromList(data);
  }

  static String _extractDocxFromBytes(Uint8List input) {
    try {
      final archive = ZipDecoder().decodeBytes(input);
      final docXml = archive.findFile('word/document.xml');
      if (docXml == null) return '[DOCX] document.xml not found';
      final xml = XmlDocument.parse(utf8.decode(docXml.content as List<int>));
      final buffer = StringBuffer();
      for (final p in xml.findAllElements('w:p')) {
        final texts = p.findAllElements('w:t');
        if (texts.isEmpty) {
          buffer.writeln();
          continue;
        }
        for (final t in texts) {
          buffer.write(t.innerText);
        }
        buffer.writeln();
      }
      return buffer.toString();
    } catch (e) {
      return '[[Failed to parse DOCX: $e]]';
    }
  }
}

