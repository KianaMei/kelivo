import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/avatar_cache.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../../utils/app_dirs.dart';

class UserProvider extends ChangeNotifier {
  static const String _prefsUserNameKey = 'user_name';
  static const String _prefsAvatarTypeKey =
      'avatar_type'; // emoji | url | file | null
  static const String _prefsAvatarValueKey = 'avatar_value';

  String _name = 'User';
  bool _hasSavedName = false;
  String? _avatarType; // 'emoji', 'url', 'file'
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
      notifyListeners();
    }

    _avatarType = prefs.getString(_prefsAvatarTypeKey);
    final rawAvatar = prefs.getString(_prefsAvatarValueKey);
    if (_avatarType == 'file' &&
        rawAvatar != null &&
        rawAvatar.trim().isNotEmpty) {
      final normalized = await _normalizeStoredAvatarValue(rawAvatar);
      _avatarValue = normalized;
      if (normalized != rawAvatar) {
        await prefs.setString(_prefsAvatarValueKey, normalized);
      }
    } else {
      final trimmed = rawAvatar?.trim();
      _avatarValue = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    if (_avatarType != null && _avatarValue != null) {
      notifyListeners();
    }
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

  Future<void> setAvatarFilePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final fixedInput = SandboxPathResolver.fix(trimmed);
    try {
      final src = File(fixedInput);
      if (!await src.exists()) return;

      final root = await AppDirs.dataRoot();
      final avatarsDir = Directory(p.join(root.path, 'avatars'));
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }

      String ext = '';
      final dot = fixedInput.lastIndexOf('.');
      if (dot != -1 && dot < fixedInput.length - 1) {
        ext = fixedInput.substring(dot + 1).toLowerCase();
        if (ext.length > 6) ext = 'jpg';
      } else {
        ext = 'jpg';
      }

      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final dest = File(p.join(avatarsDir.path, filename));
      await src.copy(dest.path);

      if (_avatarType == 'file' && _avatarValue != null) {
        try {
          final resolved = await _resolveAvatarAbsolutePath(_avatarValue!);
          if (resolved != null) {
            final normalizedResolved = p.normalize(resolved);
            final normalizedAvatarsDir = p.normalize(avatarsDir.path);
            if (p.isWithin(normalizedAvatarsDir, normalizedResolved)) {
              final old = File(normalizedResolved);
              if (await old.exists()) {
                await old.delete();
              }
            }
          }
        } catch (_) {}
      }

      _avatarType = 'file';
      final relPath = p
          .relative(dest.path, from: root.path)
          .replaceAll('\\', '/');
      _avatarValue = relPath;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsAvatarTypeKey, _avatarType!);
      await prefs.setString(_prefsAvatarValueKey, _avatarValue!);
    } catch (_) {
      final normalized = await _normalizeStoredAvatarValue(fixedInput);
      _avatarType = 'file';
      _avatarValue = normalized;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsAvatarTypeKey, _avatarType!);
      await prefs.setString(_prefsAvatarValueKey, _avatarValue!);
    }
  }

  Future<void> resetAvatar() async {
    _avatarType = null;
    _avatarValue = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAvatarTypeKey);
    await prefs.remove(_prefsAvatarValueKey);
  }

  Future<String> _normalizeStoredAvatarValue(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.startsWith('/') && !trimmed.contains(':')) {
      return trimmed.replaceAll('\\', '/');
    }

    final fixed = SandboxPathResolver.fix(trimmed);
    try {
      final root = await AppDirs.dataRoot();
      final normalizedDocs = p.normalize(root.path);
      final normalizedFile = p.normalize(fixed);
      final rel = p.relative(normalizedFile, from: normalizedDocs);
      if (!rel.startsWith('..') && !p.isAbsolute(rel)) {
        return rel.replaceAll('\\', '/');
      }
    } catch (_) {}
    return fixed;
  }

  Future<String?> _resolveAvatarAbsolutePath(String value) async {
    if (value.isEmpty) return null;
    if (value.startsWith('http')) return null;
    if (value.startsWith('/') || value.contains(':')) {
      return SandboxPathResolver.fix(value);
    }
    final root = await AppDirs.dataRoot();
    return p.join(root.path, value);
  }
}
