import 'dart:convert';

enum RestoreMode {
  overwrite, // 完全覆盖：清空本地后恢复
  merge,     // 增量合并：智能去重
}

class WebDavConfig {
  final String id;           // 唯一标识符
  final String name;         // 用户可读的名称（如 "家庭NAS"、"公司服务器"）
  final String url;
  final String username;
  final String password;
  final String path;
  final bool includeChats;   // Hive boxes
  final bool includeFiles;   // uploads/

  const WebDavConfig({
    this.id = '',
    this.name = '',
    this.url = '',
    this.username = '',
    this.password = '',
    this.path = 'kelivo_backups',
    this.includeChats = true,
    this.includeFiles = true,
  });

  /// 生成新的配置（带随机ID）
  factory WebDavConfig.create({
    String? name,
    String? url,
    String? username,
    String? password,
    String? path,
    bool includeChats = true,
    bool includeFiles = true,
  }) {
    return WebDavConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? '',
      url: url ?? '',
      username: username ?? '',
      password: password ?? '',
      path: path ?? 'kelivo_backups',
      includeChats: includeChats,
      includeFiles: includeFiles,
    );
  }

  WebDavConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? username,
    String? password,
    String? path,
    bool? includeChats,
    bool? includeFiles,
  }) {
    return WebDavConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      includeChats: includeChats ?? this.includeChats,
      includeFiles: includeFiles ?? this.includeFiles,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'path': path,
        'includeChats': includeChats,
        'includeFiles': includeFiles,
      };

  static WebDavConfig fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim() ?? '',
      password: (json['password'] as String?) ?? '',
      path: (json['path'] as String?)?.trim().isNotEmpty == true
          ? (json['path'] as String).trim()
          : 'kelivo_backups',
      includeChats: json['includeChats'] as bool? ?? true,
      includeFiles: json['includeFiles'] as bool? ?? true,
    );
  }

  static WebDavConfig fromJsonString(String s) {
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return WebDavConfig.fromJson(map);
    } catch (_) {
      return const WebDavConfig();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  /// 显示名称：优先使用 name，否则使用 URL 的 host 部分
  String get displayName {
    if (name.isNotEmpty) return name;
    if (url.isEmpty) return 'Untitled';
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : 'Untitled';
    } catch (_) {
      return 'Untitled';
    }
  }

  /// 是否为空配置
  bool get isEmpty => url.isEmpty;
  bool get isNotEmpty => url.isNotEmpty;
}

class BackupFileItem {
  final Uri href; // absolute
  final String displayName;
  final int size;
  final DateTime? lastModified;
  const BackupFileItem({
    required this.href,
    required this.displayName,
    required this.size,
    required this.lastModified,
  });
}

