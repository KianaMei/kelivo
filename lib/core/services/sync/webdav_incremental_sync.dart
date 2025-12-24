import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/backup.dart';

/// 增量同步服务
///
/// 核心思想：
/// 不再打包 zip，而是维护云端的一棵文件树：
/// /kelivo_sync_data/
///   ├── metadata.json       // 全局元数据（版本、设备锁）
///   ├── settings.json       // 设置（全量覆盖）
///   ├── conversations/      // 对话目录
///   │   ├── {uuid}.json     // 单个对话元数据
///   │   └── ...
///   ├── messages/           // 消息目录
///   │   ├── {uuid}_part0.json // 消息分片
///   │   └── ...
///   └── assets/             // 静态资源（图片/文件）
///       ├── {hash}.jpg
///       └── ...
class WebDavIncrementalSync {
  final WebDavConfig config;
  late final Dio _dio;

  WebDavIncrementalSync(this.config) {
    // 创建干净的 Dio 实例，不添加任何日志拦截器
    // 这样增量同步的请求不会污染请求日志
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ));

    // 配置 Basic Auth
    final auth = base64Encode(utf8.encode('${config.username}:${config.password}'));
    _dio.options.headers['Authorization'] = 'Basic $auth';

    // 允许自签名证书（如果需要的话，可以通过 config 控制）
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  /// 关闭 Dio 客户端，释放资源
  void close() {
    _dio.close();
  }

  String _getPath(String path) {
    String base = config.url.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    // 我们的同步根目录，硬编码以隔离备份文件
    const syncRoot = '/kelivo_sync_data';

    // 处理 path
    String rel = path.trim();
    if (rel.startsWith('/')) rel = rel.substring(1);

    return '$base$syncRoot/$rel';
  }

  /// 执行自定义 WebDAV 方法（PROPFIND, MKCOL 等）
  Future<Response<T>> _webdavRequest<T>(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType? responseType,
  }) async {
    final url = _getPath(path);
    final options = Options(
      method: method,
      headers: headers,
      responseType: responseType ?? ResponseType.plain,
      // 不验证状态码，我们自己处理
      validateStatus: (_) => true,
    );

    return _dio.request<T>(url, data: data, options: options);
  }

  /// 检查并创建根目录
  Future<void> initRemoteDir() async {
    // 检查根目录是否存在
    final check = await _webdavRequest(
      'PROPFIND',
      '',
      headers: {'Depth': '0'},
    );

    if (check.statusCode == 404) {
      // 创建根目录
      final mkcol = await _webdavRequest('MKCOL', '');
      if (mkcol.statusCode != 201 && mkcol.statusCode != 405) {
        // 405 = 目录已存在
        throw Exception('Failed to create sync root: ${mkcol.statusCode}');
      }

      // 创建子目录结构
      for (var sub in ['conversations', 'messages', 'assets']) {
        await _webdavRequest('MKCOL', '$sub/');
      }
    }
  }

  /// 获取云端文件列表（文件名 -> 修改时间/ETag）
  Future<Map<String, RemoteFileInfo>> listRemoteFiles(String subdir) async {
    final path = subdir.endsWith('/') ? subdir : '$subdir/';

    final res = await _webdavRequest<String>(
      'PROPFIND',
      path,
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      data: '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getlastmodified/>
    <d:getcontentlength/>
    <d:getetag/>
  </d:prop>
</d:propfind>''',
    );

    if (res.statusCode == 404) {
      return {}; // 目录不存在，视为空
    }
    if (res.statusCode! >= 300) {
      throw Exception('PROPFIND failed: ${res.statusCode}');
    }

    final result = <String, RemoteFileInfo>{};
    final doc = XmlDocument.parse(res.data ?? '');

    // 获取请求目录的路径，用于跳过目录本身
    final requestedUri = Uri.parse(_getPath(path));
    final requestedPath = requestedUri.path.endsWith('/') ? requestedUri.path : '${requestedUri.path}/';

    final responses = doc.findAllElements('response', namespace: '*');
    for (final resp in responses) {
      final href = resp.getElement('href', namespace: '*')?.innerText;
      if (href == null) continue;

      // 解析文件名
      final uriPath = Uri.parse(href).path;
      final name = p.basename(uriPath);

      // 跳过目录本身：如果 href 路径与请求的目录路径相同（或者只差一个尾部斜杠）
      final hrefNormalized = uriPath.endsWith('/') ? uriPath : '$uriPath/';
      if (name.isEmpty || hrefNormalized == requestedPath) continue;

      // 解析时间
      String? lastModStr;
      try {
        lastModStr = resp.findAllElements('getlastmodified', namespace: '*').firstOrNull?.innerText;
      } catch (_) {}

      // 解析大小
      int size = 0;
      try {
        final sizeStr = resp.findAllElements('getcontentlength', namespace: '*').firstOrNull?.innerText;
        size = int.tryParse(sizeStr ?? '0') ?? 0;
      } catch (_) {}

      if (lastModStr != null) {
        // HTTP Date format: Sat, 19 Jan 2025 12:00:00 GMT
        try {
          final modTime = HttpDate.parse(lastModStr);
          result[name] = RemoteFileInfo(name, modTime, size);
        } catch (_) {
          // 忽略解析错误
        }
      }
    }
    return result;
  }

  /// 上传单个 JSON 对象
  Future<void> uploadJson(String path, Map<String, dynamic> data) async {
    final url = _getPath(path);
    final body = jsonEncode(data);

    final res = await _dio.put(
      url,
      data: body,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (_) => true,
      ),
    );

    if (res.statusCode! >= 300) {
      throw Exception('Upload failed for $path: ${res.statusCode}');
    }
  }

  /// 上传文件（assets）
  /// 如果云端已经存在同名文件（且大小一致），跳过上传
  Future<void> uploadAsset(File localFile, String remoteName) async {
    final url = _getPath('assets/$remoteName');
    final length = await localFile.length();

    // 读取文件为字节数组（Dio 流式上传需要特殊处理，这里简化为读取全部）
    final bytes = await localFile.readAsBytes();

    final res = await _dio.put(
      url,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': length.toString(),
        },
        validateStatus: (_) => true,
      ),
    );

    if (res.statusCode! >= 300) {
      throw Exception('Asset upload failed: ${res.statusCode}');
    }
  }

  /// 下载 JSON
  Future<Map<String, dynamic>?> downloadJson(String path) async {
    final url = _getPath(path);
    final res = await _dio.get<String>(
      url,
      options: Options(validateStatus: (_) => true),
    );

    if (res.statusCode == 404) return null;
    if (res.statusCode! >= 300) throw Exception('Download failed: ${res.statusCode}');

    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  /// 下载二进制数据（用于图片预览等）
  Future<Uint8List?> downloadBytes(String path) async {
    final url = _getPath(path);
    final res = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );

    if (res.statusCode == 404) return null;
    if (res.statusCode! >= 300) throw Exception('Download failed: ${res.statusCode}');

    return Uint8List.fromList(res.data ?? []);
  }
}

class RemoteFileInfo {
  final String name;
  final DateTime lastModified;
  final int size;

  RemoteFileInfo(this.name, this.lastModified, this.size);

  @override
  String toString() => '$name ($size bytes, $lastModified)';
}

/// 同步管理器
/// 负责协调本地 ChatService 和 WebDAV 之间的差异对比和同步
class IncrementalSyncManager {
  final WebDavIncrementalSync _api;
  final Function(String msg) _log;

  IncrementalSyncManager(WebDavConfig config, {Function(String)? logger})
      : _api = WebDavIncrementalSync(config),
        _log = logger ?? ((_) {});

  /// 执行一次完整的同步
  /// [localConversations] 本地对话列表
  /// [localMessagesFetcher] 获取指定对话的所有消息的回调
  /// [localAssetRoot] 本地数据根目录 (AppDirs.dataRoot)
  /// [localSettings] 本地全局设置 (可选)
  /// [localAssistants] 本地助手列表 (可选)
  /// [onProgress] 进度回调 (current, total, stage)
  Future<void> performSync({
    required List<Map<String, dynamic>> localConversations,
    required Future<List<Map<String, dynamic>>> Function(String convId) localMessagesFetcher,
    required String localAssetRoot,
    Map<String, dynamic>? localSettings,
    List<Map<String, dynamic>>? localAssistants,
    required Function(Map<String, dynamic> conv) onRemoteConversationFound,
    required Function(String convId, List<Map<String, dynamic>> msgs) onRemoteMessagesFound,
    Function(Map<String, dynamic> settings)? onRemoteSettingsFound,
    Function(List<Map<String, dynamic>> assistants)? onRemoteAssistantsFound,
    Function(int current, int total, String stage)? onProgress,
  }) async {
    _log('Starting incremental sync...');

    // Progress tracking
    int currentStep = 0;
    int totalSteps = 0;
    void reportProgress(String stage) {
      currentStep++;
      onProgress?.call(currentStep, totalSteps, stage);
    }

    // 1. 确保存储桶存在
    await _api.initRemoteDir();

    // 2. 并行获取云端清单
    final remoteConvsFuture = _api.listRemoteFiles('conversations');
    final remoteMsgsFuture = _api.listRemoteFiles('messages');

    // 2.1 同步设置 (Settings)
    if (localSettings != null) {
      await _syncSettings(localSettings, onRemoteSettingsFound);
    }

    // 2.2 同步助手 (Assistants)
    if (localAssistants != null) {
      await _syncAssistants(localAssistants, onRemoteAssistantsFound);
    }

    final remoteConvs = await remoteConvsFuture;
    final remoteMsgs = await remoteMsgsFuture;

    _log('Remote index fetched. Convs: ${remoteConvs.length}, Msgs: ${remoteMsgs.length}');

    // Calculate total steps for progress
    final allConvIds = <String>{
      ...localConversations.map((c) => c['id'] as String),
      ...remoteConvs.keys.map((k) => p.basenameWithoutExtension(k))
    };
    // Steps: conversations + messages per conv + assets (estimated 3 dirs)
    totalSteps = localConversations.length + remoteConvs.length + allConvIds.length + 3;
    onProgress?.call(0, totalSteps, 'Preparing...');

    // 3. 处理 Conversation 同步 (双向)
    await _syncConversations(localConversations, remoteConvs, onRemoteConversationFound, reportProgress);

    // 4. 处理 Messages 同步 (双向)
    for (final convId in allConvIds) {
      await _syncMessagesForConversation(convId, localMessagesFetcher, remoteMsgs, onRemoteMessagesFound);
      reportProgress('Messages: $convId');
    }

    // 5. 同步所有静态资源 (upload, avatars, images)
    if (localAssetRoot.isNotEmpty) {
      await _syncAllAssets(localAssetRoot, reportProgress);
    }

    onProgress?.call(totalSteps, totalSteps, 'Done');
    _log('Sync completed.');
  }

  Future<void> _syncSettings(
      Map<String, dynamic> localSettings, Function(Map<String, dynamic>)? onRemoteFound) async {
    try {
      // 检查云端 settings.json
      final remoteFiles = await _api.listRemoteFiles('');
      final remoteInfo = remoteFiles['settings.json'];

      // 简单策略：如果云端存在且较新（这里假设5分钟阈值，避免频繁冲突），则下载覆盖本地
      // 否则上传本地
      bool upload = true;
      if (remoteInfo != null && onRemoteFound != null) {
        final localTime = DateTime.tryParse(localSettings['exportedAt'] ?? '') ?? DateTime.now();
        if (remoteInfo.lastModified.isAfter(localTime.add(const Duration(minutes: 5)))) {
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
      List<Map<String, dynamic>> localAssistants, Function(List<Map<String, dynamic>>)? onRemoteFound) async {
    try {
      final remoteFiles = await _api.listRemoteFiles('');
      final remoteInfo = remoteFiles['assistants.json'];

      // Assistants 同步策略：合并
      // 1. 总是下载云端助手列表
      List<Map<String, dynamic>> remoteList = [];
      if (remoteInfo != null) {
        final data = await _api.downloadJson('assistants.json');
        if (data != null && data['items'] is List) {
          remoteList = (data['items'] as List).cast<Map<String, dynamic>>();
          if (onRemoteFound != null) {
            _log('Merging remote assistants...');
            onRemoteFound(remoteList);
          }
        }
      }

      // 2. 将本地列表（可能包含新创建的）合并后上传
      _log('Uploading assistants...');
      await _api.uploadJson('assistants.json', {'items': localAssistants, 'updatedAt': DateTime.now().toIso8601String()});
    } catch (e) {
      _log('Error syncing assistants: $e');
    }
  }

  Future<void> _syncAllAssets(String dataRoot, Function(String stage) reportProgress) async {
    // 递归同步以下目录：
    // - upload/ (聊天附件)
    // - avatars/ (助手头像)
    // - images/ (助手背景)
    final targets = ['upload', 'avatars', 'images'];

    // 为 assets/ 下创建子目录
    for (var t in targets) {
      try {
        await _api._webdavRequest('MKCOL', 'assets/$t/');
      } catch (_) {} // 忽略已存在错误
    }

    for (var subdir in targets) {
      final localDir = Directory(p.join(dataRoot, subdir));
      if (!await localDir.exists()) {
        reportProgress('Assets: $subdir');
        continue;
      }

      try {
        _log('Checking assets/$subdir...');
        final remoteAssets = await _api.listRemoteFiles('assets/$subdir');
        final localFiles = localDir.listSync().whereType<File>();

        for (final file in localFiles) {
          final name = p.basename(file.path);
          if (name.startsWith('.')) continue;

          final remote = remoteAssets[name];
          bool shouldUpload = false;

          if (remote == null) {
            shouldUpload = true;
          } else {
            final len = await file.length();
            if (len != remote.size) {
              shouldUpload = true;
            }
          }

          if (shouldUpload) {
            _log('Uploading $subdir/$name');
            try {
              await _uploadAssetToSubdir(file, subdir, name);
            } catch (e) {
              _log('Failed to upload $name: $e');
            }
          }
        }
      } catch (e) {
        _log('Error syncing $subdir: $e');
      }
      reportProgress('Assets: $subdir');
    }
  }

  Future<void> _uploadAssetToSubdir(File localFile, String subdir, String name) async {
    final url = _api._getPath('assets/$subdir/$name');
    final length = await localFile.length();
    final bytes = await localFile.readAsBytes();

    final res = await _api._dio.put(
      url,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': length.toString(),
        },
        validateStatus: (_) => true,
      ),
    );

    if (res.statusCode! >= 300) {
      throw Exception('Asset upload failed: ${res.statusCode}');
    }
  }

  /// 同步对话列表元数据
  Future<void> _syncConversations(
    List<Map<String, dynamic>> localList,
    Map<String, RemoteFileInfo> remoteIndex,
    Function(Map<String, dynamic>) onRemoteNewer,
    Function(String stage) reportProgress,
  ) async {
    final localMap = {for (var c in localList) c['id'] as String: c};

    // A. 遍历本地，决定是否上传
    for (final local in localList) {
      final id = local['id'] as String;
      final remoteFilename = '$id.json';
      final remoteInfo = remoteIndex[remoteFilename];

      final localTime = DateTime.tryParse(local['updatedAt'] ?? '') ?? DateTime(2000);

      if (remoteInfo == null) {
        // 云端没有 -> 上传
        _log('Uploading new conversation: $id');
        await _api.uploadJson('conversations/$remoteFilename', local);
      } else {
        // 云端有 -> 比较时间
        // 注意：WebDAV 时间精度可能不一致，建议增加 2秒 容差
        if (localTime.isAfter(remoteInfo.lastModified.add(const Duration(seconds: 2)))) {
          _log('Uploading updated conversation: $id');
          await _api.uploadJson('conversations/$remoteFilename', local);
        }
      }
      reportProgress('Conv: $id');
    }

    // B. 遍历云端，决定是否下载
    for (final entry in remoteIndex.entries) {
      final filename = entry.key;
      final id = p.basenameWithoutExtension(filename);
      final remoteInfo = entry.value;

      final local = localMap[id];
      bool shouldDownload = false;

      if (local == null) {
        // 本地没有 -> 下载
        shouldDownload = true;
      } else {
        final localTime = DateTime.tryParse(local['updatedAt'] ?? '') ?? DateTime(2000);
        if (remoteInfo.lastModified.isAfter(localTime.add(const Duration(seconds: 2)))) {
          // 云端比本地新 -> 下载
          shouldDownload = true;
        }
      }

      if (shouldDownload) {
        _log('Downloading newer conversation: $id');
        final data = await _api.downloadJson('conversations/$filename');
        if (data != null) {
          onRemoteNewer(data);
        }
      }
    }
  }

  /// 同步单个对话的消息记录
  /// 目前策略：文件级覆盖。如果云端新，就下载覆盖本地；如果本地新，就上传覆盖云端。
  /// 改进空间：实现真正的增量 merge (Set union)
  Future<void> _syncMessagesForConversation(
    String convId,
    Future<List<Map<String, dynamic>>> Function(String) fetchLocalMsgs,
    Map<String, RemoteFileInfo> remoteIndex,
    Function(String, List<Map<String, dynamic>>) onRemoteNewer,
  ) async {
    final remoteFilename = '$convId.json';
    final remoteInfo = remoteIndex[remoteFilename];

    // 获取本地消息
    final localMsgs = await fetchLocalMsgs(convId);

    // 计算本地"修改时间"：取最新一条消息的时间
    DateTime localLastMod = DateTime(2000);
    if (localMsgs.isNotEmpty) {
      // 假设消息按时间排序，最后一条最新
      localLastMod = DateTime.tryParse(localMsgs.last['createdAt'] ?? '') ?? DateTime(2000);
    }

    if (remoteInfo == null) {
      if (localMsgs.isNotEmpty) {
        _log('Uploading messages for: $convId (${localMsgs.length} items)');
        await _api.uploadJson('messages/$remoteFilename', {'messages': localMsgs});
      }
    } else {
      // 对比时间
      // 如果云端文件修改时间 > 本地最新消息时间 + 容差 -> 下载
      if (remoteInfo.lastModified.isAfter(localLastMod.add(const Duration(seconds: 5)))) {
        _log('Downloading messages for: $convId');
        final data = await _api.downloadJson('messages/$remoteFilename');
        if (data != null && data['messages'] is List) {
          final msgs = (data['messages'] as List).cast<Map<String, dynamic>>();
          onRemoteNewer(convId, msgs);
        }
      } else if (localLastMod.isAfter(remoteInfo.lastModified.add(const Duration(seconds: 5)))) {
        // 本地比云端新 -> 上传
        _log('Uploading newer messages for: $convId');
        await _api.uploadJson('messages/$remoteFilename', {'messages': localMsgs});
      }
    }
  }
}
