import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/avatar_cache.dart';

/// Web 版用户信息：
/// - 不使用本地文件路径；头像 “file” 类型用 dataURL 存（或 http/https）。
class UserProvider extends ChangeNotifier {
  static const String _prefsUserNameKey = 'user_name';
  static const String _prefsAvatarTypeKey = 'avatar_type'; // emoji | url | file | null
  static const String _prefsAvatarValueKey = 'avatar_value';

  String _name = 'User';
  bool _hasSavedName = false;
  String? _avatarType;
  String? _avatarValue;

  String get name => _name;
  String? get avatarType => _avatarType;
  String? get avatarValue => _avatarValue;

  UserProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_prefsUserNameKey);
    if (savedName != null && savedName.isNotEmpty) {
      _name = savedName;
      _hasSavedName = true;
    }

    _avatarType = prefs.getString(_prefsAvatarTypeKey);
    final rawAvatar = prefs.getString(_prefsAvatarValueKey)?.trim();
    _avatarValue = (rawAvatar == null || rawAvatar.isEmpty) ? null : rawAvatar;

    notifyListeners();
  }

  void setDefaultNameIfUnset(String localizedDefaultName) {
    if (_hasSavedName) return;
    final trimmed = localizedDefaultName.trim();
    if (trimmed.isEmpty) return;
    if (_name != trimmed) {
      _name = trimmed;
      notifyListeners();
    }
  }

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUserNameKey, _name);
  }

  Future<void> setAvatarEmoji(String emoji) async {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    _avatarType = 'emoji';
    _avatarValue = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAvatarTypeKey, _avatarType!);
    await prefs.setString(_prefsAvatarValueKey, _avatarValue!);
  }

  Future<void> setAvatarUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _avatarType = 'url';
    _avatarValue = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAvatarTypeKey, _avatarType!);
    await prefs.setString(_prefsAvatarValueKey, _avatarValue!);
    try {
      await AvatarCache.getPath(trimmed);
    } catch (_) {}
  }

  Future<void> setAvatarFilePath(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    // Web: value should be a dataURL (preferred) or http(s) URL.
    _avatarType = 'file';
    _avatarValue = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAvatarTypeKey, _avatarType!);
    await prefs.setString(_prefsAvatarValueKey, _avatarValue!);
  }

  Future<void> resetAvatar() async {
    _avatarType = null;
    _avatarValue = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAvatarTypeKey);
    await prefs.remove(_prefsAvatarValueKey);
  }
}

