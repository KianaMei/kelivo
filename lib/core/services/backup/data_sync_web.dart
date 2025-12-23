import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../../models/backup.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../chat/chat_service.dart';
import '../upload/upload_service.dart';
import '../http/dio_client.dart';
import '../../../utils/backup_filename.dart';

class DataSync {
  final ChatService chatService;
  DataSync({required this.chatService});

  Future<Uint8List> exportToBytes(WebDavConfig cfg) async {
    final archive = Archive();

    final settingsJson = await _exportSettingsJson();
    archive.addFile(ArchiveFile('settings.json', settingsJson.length, utf8.encode(settingsJson)));

    if (cfg.includeChats) {
      final chatsJson = await _exportChatsJson();
      archive.addFile(ArchiveFile('chats.json', chatsJson.length, utf8.encode(chatsJson)));
    }

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes ?? const <int>[]);
  }

  Future<void> restoreFromLocalBytes(Uint8List bytes, WebDavConfig cfg, {RestoreMode mode = RestoreMode.overwrite}) async {
    await _restoreFromZipBytes(bytes, cfg, mode: mode);
  }

  Future<String> _exportSettingsJson() async {
    final prefs = await SharedPreferencesAsync.instance;
    final map = await prefs.snapshot();
    return jsonEncode(map);
  }

  Future<String> _exportChatsJson() async {
    if (!chatService.initialized) {
      await chatService.init();
    }
    final conversations = chatService.getAllConversations();
    final allMsgs = <ChatMessage>[];
    final toolEvents = <String, List<Map<String, dynamic>>>{};
    for (final c in conversations) {
      final msgs = chatService.getMessages(c.id);
      allMsgs.addAll(msgs);
      for (final m in msgs) {
        if (m.role == 'assistant') {
          final ev = chatService.getToolEvents(m.id);
          if (ev.isNotEmpty) toolEvents[m.id] = ev;
        }
      }
    }
    final obj = {
      'version': 1,
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'messages': allMsgs.map((m) => m.toJson()).toList(),
      'toolEvents': toolEvents,
    };
    return jsonEncode(obj);
  }

  List<Map<String, dynamic>> _normalizeAssistantsForCrossPlatform(List<dynamic> arr) {
    String? normOne(String? raw, {required String folder}) {
      if (raw == null) return null;
      var s = raw.trim();
      if (s.isEmpty) return null;
      final lower = s.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) return s;
      s = s.replaceAll('\\', '/');
      final idx = s.indexOf('/' + folder + '/');
      if (idx >= 0) {
        final tail = s.substring(idx + 1);
        final parts = tail.split('/');
        if (parts.isNotEmpty) {
          final name = parts.lastWhere((e) => e.isNotEmpty, orElse: () => parts.last);
          return '$folder/$name';
        }
      }
      if (!s.startsWith('/') && !s.contains(':')) return s;
      final allParts = s.split(RegExp(r'[/\\]'));
      final filename = allParts.lastWhere((p) => p.trim().isNotEmpty, orElse: () => '');
      if (filename.isNotEmpty && filename.contains('.')) return '$folder/$filename';
      return null;
    }

    final out = <Map<String, dynamic>>[];
    for (final a in arr) {
      if (a is Map) {
        final m = Map<String, dynamic>.from(a);
        m['avatar'] = normOne((m['avatar'] ?? '')?.toString(), folder: 'avatars');
        m['background'] = normOne((m['background'] ?? '')?.toString(), folder: 'images');
        out.add(m);
      }
    }
    return out;
  }

  Map<String, dynamic> _normalizeProviderConfigsForCrossPlatform(Map<String, dynamic> configs) {
    String? normAvatarPath(String? raw) {
      if (raw == null) return null;
      var s = raw.trim();
      if (s.isEmpty) return null;
      final lower = s.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) return s;
      s = s.replaceAll('\\', '/');
      final hitNew = s.indexOf('/avatars/providers/');
      final hitLegacy = s.indexOf('/cache/avatars/providers/');
      final hit = (hitNew >= 0) ? hitNew : hitLegacy;
      if (hit >= 0) {
        final tail = s.substring(hit + 1);
        final parts = tail.split('/');
        if (parts.isNotEmpty) {
          final name = parts.lastWhere((e) => e.isNotEmpty, orElse: () => parts.last);
          return 'avatars/providers/$name';
        }
      }
      if (!s.startsWith('/') && !s.contains(':')) return s;
      final allParts = s.split(RegExp(r'[/\\]'));
      final filename = allParts.lastWhere((p) => p.trim().isNotEmpty, orElse: () => '');
      if (filename.isNotEmpty && filename.contains('.')) return 'avatars/providers/$filename';
      return null;
    }

    final normalized = <String, dynamic>{};
    for (final entry in configs.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map) {
        final providerConfig = Map<String, dynamic>.from(value as Map);
        if (providerConfig.containsKey('customAvatarPath')) {
          providerConfig['customAvatarPath'] = normAvatarPath((providerConfig['customAvatarPath'] ?? '')?.toString());
        }
        normalized[key] = providerConfig;
      } else {
        normalized[key] = value;
      }
    }
    return normalized;
  }

  /// Upload files from archive to gateway and return path -> URL mapping
  Future<Map<String, String>> _uploadFilesFromArchive(Archive archive) async {
    final pathToUrl = <String, String>{};

    // Find all files in avatars/, images/, upload/ directories
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name.startsWith('avatars/') ||
          name.startsWith('images/') ||
          name.startsWith('upload/') ||
          name.startsWith('cache/avatars/')) {
        try {
          final bytes = file.content as List<int>;
          if (bytes.isEmpty) continue;

          // Extract filename for upload
          final filename = name.split('/').last;
          if (filename.isEmpty) continue;

          // Upload to gateway
          final url = await UploadService.uploadBytes(
            bytes: bytes,
            fileName: filename,
          );

          // Store mapping: relative path -> gateway URL
          pathToUrl[name] = url;

          // Also store filename-only mapping for flexibility
          pathToUrl[filename] = url;

          // Store normalized path variations
          final normalized = name.replaceAll('\\', '/');
          if (normalized != name) {
            pathToUrl[normalized] = url;
          }
        } catch (e) {
          // Skip files that fail to upload
          print('Failed to upload $name: $e');
        }
      }
    }

    return pathToUrl;
  }

  /// Update assistant paths with uploaded URLs
  List<Map<String, dynamic>> _updateAssistantPathsWithUrls(
    List<dynamic> arr,
    Map<String, String> pathToUrl,
  ) {
    String? resolveUrl(String? raw, String folder) {
      if (raw == null) return null;
      var s = raw.trim();
      if (s.isEmpty) return null;

      // Already a URL, keep it
      final lower = s.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) {
        return s;
      }

      // Normalize path
      s = s.replaceAll('\\', '/');

      // Try to find in pathToUrl mapping
      // 1. Direct match
      if (pathToUrl.containsKey(s)) {
        return pathToUrl[s];
      }

      // 2. Match with folder prefix
      final withFolder = '$folder/${s.split('/').last}';
      if (pathToUrl.containsKey(withFolder)) {
        return pathToUrl[withFolder];
      }

      // 3. Match filename only
      final filename = s.split('/').last;
      if (pathToUrl.containsKey(filename)) {
        return pathToUrl[filename];
      }

      // 4. Try various path patterns
      for (final key in pathToUrl.keys) {
        if (key.endsWith('/$filename') || key == filename) {
          return pathToUrl[key];
        }
      }

      // Not found, return normalized relative path (will show placeholder)
      return '$folder/$filename';
    }

    final out = <Map<String, dynamic>>[];
    for (final a in arr) {
      if (a is Map) {
        final m = Map<String, dynamic>.from(a);
        m['avatar'] = resolveUrl((m['avatar'] ?? '')?.toString(), 'avatars');
        m['background'] = resolveUrl((m['background'] ?? '')?.toString(), 'images');
        out.add(m);
      }
    }
    return out;
  }

  /// Update provider config paths with uploaded URLs
  Map<String, dynamic> _updateProviderConfigPathsWithUrls(
    Map<String, dynamic> configs,
    Map<String, String> pathToUrl,
  ) {
    String? resolveUrl(String? raw) {
      if (raw == null) return null;
      var s = raw.trim();
      if (s.isEmpty) return null;

      // Already a URL, keep it
      final lower = s.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) {
        return s;
      }

      // Normalize path
      s = s.replaceAll('\\', '/');

      // Try to find in pathToUrl mapping
      if (pathToUrl.containsKey(s)) {
        return pathToUrl[s];
      }

      // Try filename only
      final filename = s.split('/').last;
      if (pathToUrl.containsKey(filename)) {
        return pathToUrl[filename];
      }

      // Try with avatars/providers/ prefix
      final withPrefix = 'avatars/providers/$filename';
      if (pathToUrl.containsKey(withPrefix)) {
        return pathToUrl[withPrefix];
      }

      // Try various path patterns
      for (final key in pathToUrl.keys) {
        if (key.endsWith('/$filename') || key == filename) {
          return pathToUrl[key];
        }
      }

      // Not found, return normalized relative path
      return 'avatars/providers/$filename';
    }

    final normalized = <String, dynamic>{};
    for (final entry in configs.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map) {
        final providerConfig = Map<String, dynamic>.from(value as Map);
        if (providerConfig.containsKey('customAvatarPath')) {
          providerConfig['customAvatarPath'] = resolveUrl(
            (providerConfig['customAvatarPath'] ?? '')?.toString()
          );
        }
        normalized[key] = providerConfig;
      } else {
        normalized[key] = value;
      }
    }
    return normalized;
  }

  /// Resolve user avatar path to uploaded URL
  String? _resolveUserAvatarUrl(String raw, Map<String, String> pathToUrl) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Already a URL, keep it
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:')) {
      return s;
    }

    // Normalize path
    s = s.replaceAll('\\', '/');

    // Try direct match
    if (pathToUrl.containsKey(s)) {
      return pathToUrl[s];
    }

    // Extract filename
    final filename = s.split('/').last;
    if (filename.isEmpty) return null;

    // Try filename match
    if (pathToUrl.containsKey(filename)) {
      return pathToUrl[filename];
    }

    // Try with avatars/ prefix (user avatars might be stored there)
    final withAvatars = 'avatars/$filename';
    if (pathToUrl.containsKey(withAvatars)) {
      return pathToUrl[withAvatars];
    }

    // Try with images/ prefix
    final withImages = 'images/$filename';
    if (pathToUrl.containsKey(withImages)) {
      return pathToUrl[withImages];
    }

    // Try with upload/ prefix
    final withUpload = 'upload/$filename';
    if (pathToUrl.containsKey(withUpload)) {
      return pathToUrl[withUpload];
    }

    // Try various path patterns
    for (final key in pathToUrl.keys) {
      if (key.endsWith('/$filename') || key == filename) {
        return pathToUrl[key];
      }
    }

    return null;
  }

  Future<void> _restoreFromZipBytes(Uint8List bytes, WebDavConfig cfg, {RestoreMode mode = RestoreMode.overwrite}) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Upload files from archive to gateway first (if includeFiles is enabled)
    Map<String, String> pathToUrl = {};
    if (cfg.includeFiles) {
      pathToUrl = await _uploadFilesFromArchive(archive);
    }

    String? readText(String name) {
      try {
        final f = archive.findFile(name);
        if (f == null) return null;
        return utf8.decode(f.content as List<int>);
      } catch (_) {
        return null;
      }
    }

    final settingsTxt = readText('settings.json');
    if (settingsTxt != null) {
      try {
        final map = jsonDecode(settingsTxt) as Map<String, dynamic>;
        final prefs = await SharedPreferencesAsync.instance;

        // Update assistants with uploaded URLs
        if (map.containsKey('assistants_v1')) {
          try {
            final raw = map['assistants_v1'];
            if (raw is String && raw.isNotEmpty) {
              final arr = jsonDecode(raw) as List<dynamic>;
              final updated = pathToUrl.isNotEmpty
                  ? _updateAssistantPathsWithUrls(arr, pathToUrl)
                  : _normalizeAssistantsForCrossPlatform(arr);
              map['assistants_v1'] = jsonEncode(updated);
            }
          } catch (_) {}
        }

        // Update provider configs with uploaded URLs
        if (map.containsKey('provider_configs_v1')) {
          try {
            final raw = map['provider_configs_v1'];
            if (raw is String && raw.isNotEmpty) {
              final configs = jsonDecode(raw) as Map<String, dynamic>;
              final updated = pathToUrl.isNotEmpty
                  ? _updateProviderConfigPathsWithUrls(configs, pathToUrl)
                  : _normalizeProviderConfigsForCrossPlatform(configs);
              map['provider_configs_v1'] = jsonEncode(updated);
            }
          } catch (_) {}
        }

        // Update user avatar with uploaded URL
        if (pathToUrl.isNotEmpty && map.containsKey('avatar_type') && map.containsKey('avatar_value')) {
          final avatarType = map['avatar_type'];
          final avatarValue = map['avatar_value'];
          if (avatarType == 'file' && avatarValue is String && avatarValue.isNotEmpty) {
            final resolved = _resolveUserAvatarUrl(avatarValue, pathToUrl);
            if (resolved != null && resolved != avatarValue) {
              map['avatar_value'] = resolved;
              // If resolved to http URL, change type to 'url' for proper web display
              if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
                map['avatar_type'] = 'url';
              }
            }
          }
        }

        if (mode == RestoreMode.overwrite) {
          await prefs.restore(map);
        } else {
          final existing = await prefs.snapshot();
          for (final entry in map.entries) {
            if (!existing.containsKey(entry.key)) {
              await prefs.restoreSingle(entry.key, entry.value);
            }
          }
        }
      } catch (_) {}
    }

    final chatsTxt = readText('chats.json');
    if (cfg.includeChats && chatsTxt != null) {
      try {
        final obj = jsonDecode(chatsTxt) as Map<String, dynamic>;
        final convs = (obj['conversations'] as List?)
                ?.map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const <Conversation>[];
        final msgs = (obj['messages'] as List?)
                ?.map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const <ChatMessage>[];
        final toolEvents = ((obj['toolEvents'] as Map?) ?? const <String, dynamic>{}).map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList(),
          ),
        );

        if (mode == RestoreMode.overwrite) {
          await chatService.clearAllData();
          final byConv = <String, List<ChatMessage>>{};
          for (final m in msgs) {
            (byConv[m.conversationId] ??= <ChatMessage>[]).add(m);
          }
          for (final c in convs) {
            await chatService.restoreConversation(c, byConv[c.id] ?? const <ChatMessage>[]);
          }
          for (final entry in toolEvents.entries) {
            try {
              await chatService.setToolEvents(entry.key, entry.value);
            } catch (_) {}
          }
        } else {
          final existingConvs = chatService.getAllConversations();
          final existingConvIds = existingConvs.map((c) => c.id).toSet();
          final existingMsgIds = <String>{};
          for (final conv in existingConvs) {
            existingMsgIds.addAll(chatService.getMessages(conv.id).map((m) => m.id));
          }
          final byConv = <String, List<ChatMessage>>{};
          for (final m in msgs) {
            if (!existingMsgIds.contains(m.id)) {
              (byConv[m.conversationId] ??= <ChatMessage>[]).add(m);
            }
          }
          for (final c in convs) {
            if (!existingConvIds.contains(c.id)) {
              await chatService.restoreConversation(c, byConv[c.id] ?? const <ChatMessage>[]);
            } else if (byConv.containsKey(c.id)) {
              for (final msg in byConv[c.id]!) {
                await chatService.addMessageDirectly(c.id, msg);
              }
            }
          }
          for (final entry in toolEvents.entries) {
            final e = chatService.getToolEvents(entry.key);
            if (e.isEmpty) {
              try {
                await chatService.setToolEvents(entry.key, entry.value);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
  }

  // ===== WebDAV via Gateway Proxy =====

  /// Get the Gateway base URL for WebDAV proxy
  static String get _gatewayBaseUrl {
    final location = html.window.location;
    final host = location.hostname ?? 'localhost';
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://$host:8080';
    }
    return location.origin;
  }

  /// Build WebDAV proxy URL
  String _webdavProxyUrl(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$_gatewayBaseUrl/webapi/webdav$p';
  }

  /// Get WebDAV headers for proxy
  Map<String, String> _webdavHeaders(WebDavConfig cfg) {
    return {
      'X-WebDAV-URL': cfg.url.trim(),
      'X-WebDAV-Username': cfg.username.trim(),
      'X-WebDAV-Password': cfg.password,
    };
  }

  /// Collection URI path
  String _collectionPath(WebDavConfig cfg) {
    String pathPart = cfg.path.trim();
    if (pathPart.isNotEmpty) {
      pathPart = '/${pathPart.replaceAll(RegExp(r'^/+'), '')}';
    }
    return '$pathPart/';
  }

  /// Test WebDAV connection
  Future<void> testWebdav(WebDavConfig cfg) async {
    final path = _collectionPath(cfg);
    final url = _webdavProxyUrl(path);
    final body = '<?xml version="1.0" encoding="utf-8" ?>\n'
        '<d:propfind xmlns:d="DAV:">\n'
        '  <d:prop>\n'
        '    <d:displayname/>\n'
        '  </d:prop>\n'
        '</d:propfind>';

    final res = await simpleDio.request(
      url,
      data: body,
      options: Options(
        method: 'PROPFIND',
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
          ..._webdavHeaders(cfg),
        },
        validateStatus: (status) => true,
      ),
    );

    if (res.statusCode != 207 && (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300)) {
      throw Exception('WebDAV test failed: ${res.statusCode}');
    }
  }

  /// Ensure collection exists (create if needed)
  Future<void> _ensureCollection(WebDavConfig cfg) async {
    final pathPart = cfg.path.trim().replaceAll(RegExp(r'^/+'), '');
    if (pathPart.isEmpty) return;

    final segments = pathPart.split('/').where((s) => s.isNotEmpty).toList();
    String acc = '';

    for (final seg in segments) {
      acc = acc.isEmpty ? '/$seg' : '$acc/$seg';
      final url = _webdavProxyUrl('$acc/');

      // Check if exists
      final checkRes = await simpleDio.request(
        url,
        data: '<?xml version="1.0" encoding="utf-8" ?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>',
        options: Options(
          method: 'PROPFIND',
          extra: const {kLogNetworkResultOnlyExtraKey: true},
          headers: {
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
            ..._webdavHeaders(cfg),
          },
          validateStatus: (status) => true,
        ),
      );

      if (checkRes.statusCode == 404) {
        // Create collection
        final mkRes = await simpleDio.request(
          url,
          options: Options(
            method: 'MKCOL',
            headers: _webdavHeaders(cfg),
            extra: const {kLogNetworkResultOnlyExtraKey: true},
            validateStatus: (status) => true,
          ),
        );
        if (mkRes.statusCode != 201 && mkRes.statusCode != 200 && mkRes.statusCode != 405) {
          throw Exception('Failed to create WebDAV collection: ${mkRes.statusCode}');
        }
      }
    }
  }

  /// Backup to WebDAV
  Future<void> backupToWebDav(WebDavConfig cfg) async {
    await _ensureCollection(cfg);

    final bytes = await exportToBytes(cfg);
    final filename = kelivoBackupFileName();
    final path = _collectionPath(cfg) + filename;
    final url = _webdavProxyUrl(path);

    final res = await simpleDio.request(
      url,
      data: bytes,
      options: Options(
        method: 'PUT',
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        headers: {
          'Content-Type': 'application/zip',
          ..._webdavHeaders(cfg),
        },
        validateStatus: (status) => true,
      ),
    );

    if (res.statusCode != 201 && res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to upload backup: ${res.statusCode}');
    }
  }

  /// List backup files from WebDAV
  Future<List<BackupFileItem>> listBackupFiles(WebDavConfig cfg) async {
    final path = _collectionPath(cfg);
    final url = _webdavProxyUrl(path);
    final body = '<?xml version="1.0" encoding="utf-8" ?>\n'
        '<d:propfind xmlns:d="DAV:">\n'
        '  <d:prop>\n'
        '    <d:displayname/>\n'
        '    <d:getcontentlength/>\n'
        '    <d:getlastmodified/>\n'
        '  </d:prop>\n'
        '</d:propfind>';

    final res = await simpleDio.request(
      url,
      data: body,
      options: Options(
        method: 'PROPFIND',
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
          ..._webdavHeaders(cfg),
        },
        validateStatus: (status) => true,
        responseType: ResponseType.plain,
      ),
    );

    if (res.statusCode != 207) {
      if (res.statusCode == 404) return [];
      throw Exception('Failed to list backups: ${res.statusCode}');
    }

    final items = <BackupFileItem>[];
    try {
      final doc = XmlDocument.parse(res.data.toString());
      final responses = [
        ...doc.findAllElements('d:response', namespace: 'DAV:'),
        ...doc.findAllElements('D:response'),
        ...doc.findAllElements('response'),
      ];
      for (final response in responses) {
        final href = response.findElements('d:href').firstOrNull?.innerText ??
            response.findElements('D:href').firstOrNull?.innerText ??
            response.findElements('href').firstOrNull?.innerText ??
            '';
        if (href.isEmpty || href.endsWith('/')) continue;

        final displayName = response.findAllElements('d:displayname').firstOrNull?.innerText ??
            response.findAllElements('D:displayname').firstOrNull?.innerText ??
            response.findAllElements('displayname').firstOrNull?.innerText ??
            href.split('/').last;

        if (!displayName.toLowerCase().endsWith('.zip')) continue;

        final sizeStr = response.findAllElements('d:getcontentlength').firstOrNull?.innerText ??
            response.findAllElements('D:getcontentlength').firstOrNull?.innerText ??
            response.findAllElements('getcontentlength').firstOrNull?.innerText ??
            '0';

        final modStr = response.findAllElements('d:getlastmodified').firstOrNull?.innerText ??
            response.findAllElements('D:getlastmodified').firstOrNull?.innerText ??
            response.findAllElements('getlastmodified').firstOrNull?.innerText;

        DateTime? lastMod;
        if (modStr != null && modStr.isNotEmpty) {
          try {
            lastMod = DateTime.parse(modStr);
          } catch (_) {
            // Try parsing as HTTP date format (e.g., "Thu, 01 Jan 1970 00:00:00 GMT")
            try {
              // Simple HTTP date parser for web
              lastMod = _parseHttpDate(modStr);
            } catch (_) {}
          }
        }

        items.add(BackupFileItem(
          href: Uri.parse(cfg.url).resolve(href),
          displayName: displayName,
          size: int.tryParse(sizeStr) ?? 0,
          lastModified: lastMod,
        ));
      }
    } catch (e) {
      print('Failed to parse WebDAV response: $e');
    }

    items.sort((a, b) => (b.lastModified ?? DateTime(1970)).compareTo(a.lastModified ?? DateTime(1970)));
    return items;
  }

  /// Restore from WebDAV
  Future<void> restoreFromWebDav(WebDavConfig cfg, BackupFileItem item, {RestoreMode mode = RestoreMode.overwrite}) async {
    // Extract the path from the item href relative to the WebDAV URL
    final itemPath = item.href.path;
    final url = _webdavProxyUrl(itemPath);

    final res = await simpleDio.request(
      url,
      options: Options(
        method: 'GET',
        headers: _webdavHeaders(cfg),
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        responseType: ResponseType.bytes,
        validateStatus: (status) => true,
      ),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to download backup: ${res.statusCode}');
    }

    final bytes = Uint8List.fromList(res.data as List<int>);
    await restoreFromLocalBytes(bytes, cfg, mode: mode);
  }

  /// Delete backup file from WebDAV
  Future<void> deleteWebDavBackupFile(WebDavConfig cfg, BackupFileItem item) async {
    final itemPath = item.href.path;
    final url = _webdavProxyUrl(itemPath);

    final res = await simpleDio.request(
      url,
      options: Options(
        method: 'DELETE',
        headers: _webdavHeaders(cfg),
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        validateStatus: (status) => true,
      ),
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to delete backup: ${res.statusCode}');
    }
  }

  /// Simple HTTP date parser for web
  static DateTime? _parseHttpDate(String dateStr) {
    // Parse HTTP date format: "Thu, 01 Jan 1970 00:00:00 GMT"
    try {
      final parts = dateStr.split(' ');
      if (parts.length < 5) return null;

      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final monthIndex = months.indexOf(parts[2]);
      if (monthIndex == -1) return null;

      final day = int.parse(parts[1]);
      final year = int.parse(parts[3]);
      final timeParts = parts[4].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);

      return DateTime.utc(year, monthIndex + 1, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

class SharedPreferencesAsync {
  SharedPreferencesAsync._();
  static SharedPreferencesAsync? _inst;
  static Future<SharedPreferencesAsync> get instance async {
    _inst ??= SharedPreferencesAsync._();
    return _inst!;
  }

  Future<Map<String, dynamic>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final map = <String, dynamic>{};
    for (final k in keys) {
      map[k] = prefs.get(k);
    }
    return map;
  }

  Future<void> restore(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.entries) {
      final k = entry.key;
      final v = entry.value;
      if (v is bool) await prefs.setBool(k, v);
      else if (v is int) await prefs.setInt(k, v);
      else if (v is double) await prefs.setDouble(k, v);
      else if (v is String) await prefs.setString(k, v);
      else if (v is List) {
        await prefs.setStringList(k, v.whereType<String>().toList());
      }
    }
  }

  Future<void> restoreSingle(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    else if (value is int) await prefs.setInt(key, value);
    else if (value is double) await prefs.setDouble(key, value);
    else if (value is String) await prefs.setString(key, value);
    else if (value is List) {
      await prefs.setStringList(key, value.whereType<String>().toList());
    }
  }
}

