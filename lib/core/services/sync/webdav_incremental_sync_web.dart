import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../models/backup.dart';
import '../http/dio_client.dart';

/// Web 版增量同步服务
///
/// 通过 Gateway 代理实现 WebDAV 操作
/// 同步结构：
/// /kelivo_sync_data/
///   ├── metadata.json       // 全局元数据
///   ├── settings.json       // 设置
///   ├── assistants.json     // 助手列表
///   ├── conversations/      // 对话目录
///   │   └── {uuid}.json
///   └── messages/           // 消息目录
///       └── {uuid}.json
class WebDavIncrementalSyncWeb {
  final WebDavConfig config;

  WebDavIncrementalSyncWeb(this.config);

  /// Gateway base URL
  static String get _gatewayBaseUrl {
    final location = html.window.location;
    final host = location.hostname ?? 'localhost';
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://$host:8080';
    }
    return location.origin;
  }

  /// 构建代理 URL
  String _proxyUrl(String path) {
    final syncRoot = '/kelivo_sync_data';
    String rel = path.trim();
    if (rel.startsWith('/')) rel = rel.substring(1);
    final fullPath = '$syncRoot/$rel';
    final p = fullPath.startsWith('/') ? fullPath : '/$fullPath';
    return '$_gatewayBaseUrl/webapi/webdav$p';
  }

  /// WebDAV 代理请求头
  Map<String, String> _headers() {
    return {
      'X-WebDAV-URL': config.url.trim(),
      'X-WebDAV-Username': config.username.trim(),
      'X-WebDAV-Password': config.password,
    };
  }

  /// 执行 WebDAV 请求
  Future<Response<T>> _request<T>(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? extraHeaders,
    ResponseType? responseType,
  }) async {
    final url = _proxyUrl(path);
    final headers = <String, dynamic>{
      ..._headers(),
      if (extraHeaders != null) ...extraHeaders,
    };

    return simpleDio.request<T>(
      url,
      data: data,
      options: Options(
        method: method,
        headers: headers,
        responseType: responseType ?? ResponseType.plain,
        extra: const {kLogNetworkResultOnlyExtraKey: true},
        validateStatus: (_) => true,
      ),
    );
  }

  /// 初始化远程目录结构
  Future<void> initRemoteDir() async {
    // 检查根目录
    final check = await _request('PROPFIND', '', extraHeaders: {'Depth': '0'});

    if (check.statusCode == 404) {
      // 创建根目录
      final mkcol = await _request('MKCOL', '');
      if (mkcol.statusCode != 201 && mkcol.statusCode != 405) {
        throw Exception('Failed to create sync root: ${mkcol.statusCode}');
      }

      // 创建子目录
      for (var sub in ['conversations', 'messages']) {
        await _request('MKCOL', '$sub/');
      }
    }
  }

  /// 获取远程文件列表
  Future<Map<String, RemoteFileInfoWeb>> listRemoteFiles(String subdir) async {
    final path = subdir.endsWith('/') ? subdir : '$subdir/';

    final res = await _request<String>(
      'PROPFIND',
      path,
      extraHeaders: {'Depth': '1', 'Content-Type': 'application/xml'},
      data: '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getlastmodified/>
    <d:getcontentlength/>
  </d:prop>
</d:propfind>''',
    );

    if (res.statusCode == 404) return {};
    if (res.statusCode! >= 300) {
      throw Exception('PROPFIND failed: ${res.statusCode}');
    }

    final result = <String, RemoteFileInfoWeb>{};
    try {
      final doc = XmlDocument.parse(res.data ?? '');
      final responses = [
        ...doc.findAllElements('d:response', namespace: 'DAV:'),
        ...doc.findAllElements('D:response'),
        ...doc.findAllElements('response'),
      ];

      for (final resp in responses) {
        final href = resp.findElements('d:href').firstOrNull?.innerText ??
            resp.findElements('D:href').firstOrNull?.innerText ??
            resp.findElements('href').firstOrNull?.innerText ??
            '';
        if (href.isEmpty || href.endsWith('/')) continue;

        final name = Uri.parse(href).pathSegments.lastOrNull ?? '';
        if (name.isEmpty) continue;

        // 解析修改时间
        final lastModStr = resp.findAllElements('d:getlastmodified').firstOrNull?.innerText ??
            resp.findAllElements('D:getlastmodified').firstOrNull?.innerText ??
            resp.findAllElements('getlastmodified').firstOrNull?.innerText;

        // 解析大小
        final sizeStr = resp.findAllElements('d:getcontentlength').firstOrNull?.innerText ??
            resp.findAllElements('D:getcontentlength').firstOrNull?.innerText ??
            resp.findAllElements('getcontentlength').firstOrNull?.innerText ??
            '0';
        final size = int.tryParse(sizeStr) ?? 0;

        DateTime? modTime;
        if (lastModStr != null) {
          modTime = _parseHttpDate(lastModStr);
        }

        result[name] = RemoteFileInfoWeb(name, modTime ?? DateTime(2000), size);
      }
    } catch (e) {
      print('Failed to parse PROPFIND response: $e');
    }

    return result;
  }

  /// 上传 JSON 数据
  Future<void> uploadJson(String path, Map<String, dynamic> data) async {
    final body = jsonEncode(data);
    final res = await _request(
      'PUT',
      path,
      data: body,
      extraHeaders: {'Content-Type': 'application/json'},
    );

    if (res.statusCode! >= 300) {
      throw Exception('Upload failed for $path: ${res.statusCode}');
    }
  }

  /// 下载 JSON 数据
  Future<Map<String, dynamic>?> downloadJson(String path) async {
    final res = await _request<String>('GET', path);

    if (res.statusCode == 404) return null;
    if (res.statusCode! >= 300) {
      throw Exception('Download failed: ${res.statusCode}');
    }

    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  /// 解析 HTTP 日期格式
  static DateTime? _parseHttpDate(String dateStr) {
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

class RemoteFileInfoWeb {
  final String name;
  final DateTime lastModified;
  final int size;

  RemoteFileInfoWeb(this.name, this.lastModified, this.size);

  @override
  String toString() => '$name ($size bytes, $lastModified)';
}

/// Web 版增量同步管理器
class IncrementalSyncManagerWeb {
  final WebDavIncrementalSyncWeb _api;
  final Function(String msg) _log;

  IncrementalSyncManagerWeb(WebDavConfig config, {Function(String)? logger})
      : _api = WebDavIncrementalSyncWeb(config),
        _log = logger ?? ((_) {});

  /// 执行完整同步
  Future<void> performSync({
    required List<Map<String, dynamic>> localConversations,
    required Future<List<Map<String, dynamic>>> Function(String convId) localMessagesFetcher,
    Map<String, dynamic>? localSettings,
    List<Map<String, dynamic>>? localAssistants,
    required Function(Map<String, dynamic> conv) onRemoteConversationFound,
    required Function(String convId, List<Map<String, dynamic>> msgs) onRemoteMessagesFound,
    Function(Map<String, dynamic> settings)? onRemoteSettingsFound,
    Function(List<Map<String, dynamic>> assistants)? onRemoteAssistantsFound,
    Function(int current, int total, String stage)? onProgress,
  }) async {
    _log('Starting incremental sync (Web)...');

    int completedSteps = 0;
    void reportProgress(int total, String stage) {
      completedSteps++;
      onProgress?.call(completedSteps, total, stage);
    }

    // 1. 确保远程目录存在
    await _api.initRemoteDir();

    // 2. 获取远程索引
    final remoteConvs = await _api.listRemoteFiles('conversations');
    final remoteMsgs = await _api.listRemoteFiles('messages');
    final remoteRoot = await _api.listRemoteFiles('');

    _log('Remote index: Convs=${remoteConvs.length}, Msgs=${remoteMsgs.length}');

    // 计算总步骤
    final allConvIds = <String>{
      ...localConversations.map((c) => c['id'] as String),
      ...remoteConvs.keys.map((k) => k.replaceAll('.json', '')),
    };
    final totalSteps = 2 + allConvIds.length * 2; // settings + assistants + convs + msgs
    onProgress?.call(0, totalSteps, 'Preparing');

    // 3. 同步 Settings
    if (localSettings != null) {
      await _syncSettings(localSettings, remoteRoot, onRemoteSettingsFound);
      reportProgress(totalSteps, 'Settings');
    } else {
      reportProgress(totalSteps, 'Settings');
    }

    // 4. 同步 Assistants
    if (localAssistants != null) {
      await _syncAssistants(localAssistants, remoteRoot, onRemoteAssistantsFound);
      reportProgress(totalSteps, 'Assistants');
    } else {
      reportProgress(totalSteps, 'Assistants');
    }

    // 5. 同步 Messages（必须先于 Conversations，确保消息存在后再合并 messageIds）
    for (final convId in allConvIds) {
      await _syncMessages(convId, localMessagesFetcher, remoteMsgs, onRemoteMessagesFound);
      reportProgress(totalSteps, 'Messages');
    }

    // 6. 同步 Conversations（在消息同步完成后进行）
    final localConvMap = {for (var c in localConversations) c['id'] as String: c};
    for (final id in allConvIds) {
      await _syncConversation(id, localConvMap[id], remoteConvs, onRemoteConversationFound);
      reportProgress(totalSteps, 'Conversations');
    }

    _log('Sync completed.');
  }

  Future<void> _syncSettings(
    Map<String, dynamic> localSettings,
    Map<String, RemoteFileInfoWeb> remoteRoot,
    Function(Map<String, dynamic>)? onRemoteFound,
  ) async {
    try {
      final remoteInfo = remoteRoot['settings.json'];
      bool upload = true;

      if (remoteInfo != null && onRemoteFound != null) {
        final localTime = DateTime.tryParse(localSettings['exportedAt'] ?? '') ?? DateTime.now();
        if (remoteInfo.lastModified.isAfter(localTime.add(const Duration(seconds: 2)))) {
          _log('Downloading newer settings...');
          final remoteData = await _api.downloadJson('settings.json');
          if (remoteData != null) {
            onRemoteFound(remoteData);
            upload = false;
          }
        }
      }

      if (upload) {
        _log('Uploading settings...');
        await _api.uploadJson('settings.json', localSettings);
      }
    } catch (e) {
      _log('Error syncing settings: $e');
    }
  }

  Future<void> _syncAssistants(
    List<Map<String, dynamic>> localAssistants,
    Map<String, RemoteFileInfoWeb> remoteRoot,
    Function(List<Map<String, dynamic>>)? onRemoteFound,
  ) async {
    try {
      final remoteInfo = remoteRoot['assistants.json'];

      if (remoteInfo != null) {
        final data = await _api.downloadJson('assistants.json');
        if (data != null && data['items'] is List) {
          final remoteList = (data['items'] as List).cast<Map<String, dynamic>>();
          if (onRemoteFound != null) {
            _log('Merging remote assistants...');
            onRemoteFound(remoteList);
          }
        }
      }

      _log('Uploading assistants...');
      await _api.uploadJson('assistants.json', {
        'items': localAssistants,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _log('Error syncing assistants: $e');
    }
  }

  Future<void> _syncConversation(
    String id,
    Map<String, dynamic>? local,
    Map<String, RemoteFileInfoWeb> remoteIndex,
    Function(Map<String, dynamic>) onRemoteNewer,
  ) async {
    final remoteFilename = '$id.json';
    final remoteInfo = remoteIndex[remoteFilename];

    if (local != null) {
      final localTime = DateTime.tryParse(local['updatedAt'] ?? '') ?? DateTime(2000);

      if (remoteInfo == null) {
        _log('Uploading new conversation: $id');
        await _api.uploadJson('conversations/$remoteFilename', local);
      } else if (localTime.isAfter(remoteInfo.lastModified.add(const Duration(seconds: 2)))) {
        _log('Uploading updated conversation: $id');
        await _api.uploadJson('conversations/$remoteFilename', local);
      } else if (remoteInfo.lastModified.isAfter(localTime.add(const Duration(seconds: 2)))) {
        _log('Downloading newer conversation: $id');
        final data = await _api.downloadJson('conversations/$remoteFilename');
        if (data != null) onRemoteNewer(data);
      }
    } else if (remoteInfo != null) {
      _log('Downloading new conversation: $id');
      final data = await _api.downloadJson('conversations/$remoteFilename');
      if (data != null) onRemoteNewer(data);
    }
  }

  Future<void> _syncMessages(
    String convId,
    Future<List<Map<String, dynamic>>> Function(String) fetchLocalMsgs,
    Map<String, RemoteFileInfoWeb> remoteIndex,
    Function(String, List<Map<String, dynamic>>) onRemoteNewer,
  ) async {
    final remoteFilename = '$convId.json';
    final remoteInfo = remoteIndex[remoteFilename];

    final localMsgs = await fetchLocalMsgs(convId);

    DateTime localLastMod = DateTime(2000);
    if (localMsgs.isNotEmpty) {
      localLastMod = DateTime.tryParse(localMsgs.last['timestamp'] ?? '') ?? DateTime(2000);
    }

    if (remoteInfo == null) {
      if (localMsgs.isNotEmpty) {
        _log('Uploading messages for: $convId (${localMsgs.length} items)');
        await _api.uploadJson('messages/$remoteFilename', {'messages': localMsgs});
      }
    } else {
      if (remoteInfo.lastModified.isAfter(localLastMod.add(const Duration(seconds: 5)))) {
        _log('Downloading messages for: $convId');
        final data = await _api.downloadJson('messages/$remoteFilename');
        if (data != null && data['messages'] is List) {
          final msgs = (data['messages'] as List).cast<Map<String, dynamic>>();
          onRemoteNewer(convId, msgs);
        }
      } else if (localLastMod.isAfter(remoteInfo.lastModified.add(const Duration(seconds: 5)))) {
        _log('Uploading newer messages for: $convId');
        await _api.uploadJson('messages/$remoteFilename', {'messages': localMsgs});
      }
    }
  }
}
