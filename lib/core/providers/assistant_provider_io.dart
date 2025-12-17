import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../../utils/sandbox_path_resolver.dart';
import '../models/assistant.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/avatar_cache.dart';
import 'package:path/path.dart' as p;
import '../../utils/app_dirs.dart';

class AssistantProvider extends ChangeNotifier {
  static const String _assistantsKey = 'assistants_v1';
  static const String _currentAssistantKey = 'current_assistant_id_v1';

  // Default OCR prompt (same as in SettingsProvider)
  static const String _defaultOcrPrompt = '''You are an OCR assistant.

Extract all visible text from the image and also describe any non-text elements (icons, shapes, arrows, objects, symbols, or emojis).

Please ensure:
- Preserve original formatting as much as possible
- Keep hierarchical structure (headings, lists, tables)
- Describe visual elements that convey meaning
- Keep the original reading order and layout structure as much as possible.

Do not interpret or translate—only transcribe and describe what is visually present.''';

  final List<Assistant> _assistants = <Assistant>[];
  String? _currentAssistantId;

  List<Assistant> get assistants => List.unmodifiable(_assistants);
  String? get currentAssistantId => _currentAssistantId;
  Assistant? get currentAssistant {
    final idx = _assistants.indexWhere((a) => a.id == _currentAssistantId);
    if (idx != -1) return _assistants[idx];
    if (_assistants.isNotEmpty) return _assistants.first;
    return null;
  }

  AssistantProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_assistantsKey);
    if (raw != null && raw.isNotEmpty) {
      _assistants
        ..clear()
        ..addAll(Assistant.decodeList(raw));
      // Note: Paths are stored as relative paths (avatars/xxx.jpg)
      // They will be resolved to absolute paths when needed for display
    }
    // Do not create defaults here because localization is not available.
    // Defaults will be ensured later via ensureDefaults(context).
    // Restore current assistant if present
    final savedId = prefs.getString(_currentAssistantKey);
    if (savedId != null && _assistants.any((a) => a.id == savedId)) {
      _currentAssistantId = savedId;
    } else {
      _currentAssistantId = null;
    }
    notifyListeners();
  }

  Assistant _defaultAssistant(AppLocalizations l10n) => Assistant(
        id: const Uuid().v4(),
        name: l10n.assistantProviderDefaultAssistantName,
        systemPrompt: '',
        deletable: false,
        temperature: 0.6,
        topP: 1.0,
      );

  // Ensure localized default assistants exist; call this after localization is ready.
  Future<void> ensureDefaults(dynamic context) async {
    if (_assistants.isNotEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    // 1) 默认助手
    _assistants.add(_defaultAssistant(l10n));
    // 2) 示例助手（带提示词模板）
    _assistants.add(Assistant(
      id: const Uuid().v4(),
      name: l10n.assistantProviderSampleAssistantName,
      systemPrompt: l10n.assistantProviderSampleAssistantSystemPrompt(
        '{model_name}',
        '{cur_datetime}',
        '"{locale}"',
        '{timezone}',
        '{device_info}',
        '{system_version}',
      ),
      deletable: false,
      temperature: 0.6,
      topP: 1.0,
    ));
    // 3) OCR 助手
    _assistants.add(Assistant(
      id: const Uuid().v4(),
      name: l10n.assistantProviderOcrAssistantName,
      systemPrompt: _defaultOcrPrompt,
      deletable: false,
      temperature: 0.6,
      topP: 1.0,
    ));
    await _persist();
    // Set current assistant if not set
    if (_currentAssistantId == null && _assistants.isNotEmpty) {
      _currentAssistantId = _assistants.first.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentAssistantKey, _currentAssistantId!);
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_assistantsKey, Assistant.encodeList(_assistants));
  }

  Future<void> setCurrentAssistant(String id) async {
    if (_currentAssistantId == id) return;
    _currentAssistantId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentAssistantKey, id);
  }

  Assistant? getById(String id) {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return null;
    return _assistants[idx];
  }

  Future<String> addAssistant({String? name, dynamic context}) async {
    final a = Assistant(
      id: const Uuid().v4(),
      name: (name ??
          (context != null
              ? AppLocalizations.of(context)!.assistantProviderNewAssistantName
              : 'New Assistant')),
      temperature: 0.6,
      topP: 1.0,
    );
    _assistants.add(a);
    await _persist();
    notifyListeners();
    return a.id;
  }

  Future<void> updateAssistant(Assistant updated) async {
    final idx = _assistants.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;

    var next = updated;

    // If avatar changed and is a local file path (from gallery/cache),
    // copy it to persistent Documents/avatars and store that path.
    try {
      final prev = _assistants[idx];
      final raw = (updated.avatar ?? '').trim();
      final prevRaw = (prev.avatar ?? '').trim();
      final changed = raw != prevRaw;
      final isLocalPath =
          raw.isNotEmpty && (raw.startsWith('/') || raw.contains(':')) && !raw.startsWith('http');
      // Skip if it's already under our avatars folder (normalize path separators for cross-platform check)
      final normalizedRaw = raw.replaceAll('\\', '/');
      if (changed && isLocalPath && !normalizedRaw.contains('avatars/')) {
        final fixedInput = SandboxPathResolver.fix(raw);
        final src = File(fixedInput);
        if (await src.exists()) {
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
          final filename = 'assistant_${updated.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final dest = File('${avatarsDir.path}/$filename');
          await src.copy(dest.path);

          // Optionally remove old stored avatar
          if (prevRaw.isNotEmpty) {
            try {
              final oldAbsPath = await resolveToAbsolutePath(prevRaw);
              if (oldAbsPath != null) {
                final old = File(oldAbsPath);
                if (await old.exists() && old.path != dest.path) {
                  await old.delete();
                }
              }
            } catch (_) {}
          }

          // Store RELATIVE path for cross-platform compatibility
          next = updated.copyWith(avatar: 'avatars/$filename');
        }
      }

      // Prefetch URL avatar to allow offline display later
      if (changed && raw.startsWith('http')) {
        try {
          await AvatarCache.getPath(raw);
        } catch (_) {}
      }

      // Handle background persistence similar to avatar, but under images/
      final bgRaw = (updated.background ?? '').trim();
      final prevBgRaw = (prev.background ?? '').trim();
      final bgChanged = bgRaw != prevBgRaw;
      final bgIsLocal =
          bgRaw.isNotEmpty && (bgRaw.startsWith('/') || bgRaw.contains(':')) && !bgRaw.startsWith('http');
      // Skip if it's already under our images folder (normalize path separators for cross-platform check)
      final normalizedBgRaw = bgRaw.replaceAll('\\', '/');
      if (bgChanged && bgIsLocal && !normalizedBgRaw.contains('images/')) {
        final fixedBg = SandboxPathResolver.fix(bgRaw);
        final srcBg = File(fixedBg);
        if (await srcBg.exists()) {
          final root = await AppDirs.dataRoot();
          final imagesDir = Directory(p.join(root.path, 'images'));
          if (!await imagesDir.exists()) {
            await imagesDir.create(recursive: true);
          }
          String ext = '';
          final dot = fixedBg.lastIndexOf('.');
          if (dot != -1 && dot < fixedBg.length - 1) {
            ext = fixedBg.substring(dot + 1).toLowerCase();
            if (ext.length > 6) ext = 'jpg';
          } else {
            ext = 'jpg';
          }
          final filename = 'background_${updated.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final destBg = File('${imagesDir.path}/$filename');
          await srcBg.copy(destBg.path);

          // Clean old stored background
          if (prevBgRaw.isNotEmpty) {
            try {
              final oldAbsPath = await resolveToAbsolutePath(prevBgRaw);
              if (oldAbsPath != null) {
                final oldBg = File(oldAbsPath);
                if (await oldBg.exists() && oldBg.path != destBg.path) {
                  await oldBg.delete();
                }
              }
            } catch (_) {}
          }

          // Store RELATIVE path for cross-platform compatibility
          next = next.copyWith(background: 'images/$filename');
        }
      } else if (bgChanged && bgRaw.isEmpty && prevBgRaw.isNotEmpty) {
        // If background cleared, optionally remove previous stored file
        try {
          final oldAbsPath = await resolveToAbsolutePath(prevBgRaw);
          if (oldAbsPath != null) {
            final oldBg = File(oldAbsPath);
            if (await oldBg.exists()) {
              await oldBg.delete();
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      // On any failure, fall back to the provided value unchanged.
    }

    _assistants[idx] = next;
    await _persist();
    notifyListeners();
  }

  /// Convert path to absolute path for file operations
  /// Handles both relative paths (avatars/xxx.jpg) and absolute paths
  static Future<String?> resolveToAbsolutePath(String path) async {
    if (path.isEmpty) return null;
    if (path.startsWith('http')) return null; // Skip URLs

    // If it's a relative path, prepend app data root for cross-platform consistency
    if (!path.startsWith('/') && !path.contains(':')) {
      final root = await AppDirs.dataRoot();
      return p.join(root.path, path);
    }

    // Already absolute - use SandboxPathResolver for iOS compatibility
    return SandboxPathResolver.fix(path);
  }

  Future<void> deleteAssistant(String id) async {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    if (!_assistants[idx].deletable) return; // default not deletable
    final removingCurrent = _assistants[idx].id == _currentAssistantId;
    _assistants.removeAt(idx);
    if (removingCurrent) {
      _currentAssistantId = _assistants.isNotEmpty ? _assistants.first.id : null;
    }
    await _persist();
    final prefs = await SharedPreferences.getInstance();
    if (_currentAssistantId != null) {
      await prefs.setString(_currentAssistantKey, _currentAssistantId!);
    } else {
      await prefs.remove(_currentAssistantKey);
    }
    notifyListeners();
  }

  Future<void> reorderAssistants(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _assistants.length) return;
    if (newIndex < 0 || newIndex >= _assistants.length) return;

    final assistant = _assistants.removeAt(oldIndex);
    _assistants.insert(newIndex, assistant);

    // Notify listeners immediately for smooth UI update
    notifyListeners();

    // Then persist the changes
    await _persist();
  }

  Future<void> reorderAssistantsWithin({
    required List<String> subsetIds,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (oldIndex == newIndex) return;
    if (subsetIds.isEmpty) return;

    final idSet = subsetIds.toSet();
    final subsetIndices = <int>[];
    for (int i = 0; i < _assistants.length; i++) {
      if (idSet.contains(_assistants[i].id)) subsetIndices.add(i);
    }
    if (subsetIndices.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= subsetIndices.length) return;
    if (newIndex < 0 || newIndex >= subsetIndices.length) return;

    final from = subsetIndices[oldIndex];
    final to = subsetIndices[newIndex];
    final item = _assistants.removeAt(from);
    _assistants.insert(to, item);
    notifyListeners();
    await _persist();
  }
}

