import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/assistant.dart';
import '../models/assistant_regex.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/avatar_cache.dart';

/// Web 版 AssistantProvider：
/// - 头像/背景不落本地文件；使用 `data:` URL 或 http(s) URL 直接存储。
class AssistantProvider extends ChangeNotifier {
  static const String _assistantsKey = 'assistants_v1';
  static const String _currentAssistantKey = 'current_assistant_id_v1';

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
    }
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

  Future<void> ensureDefaults(dynamic context) async {
    if (_assistants.isNotEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    _assistants.add(_defaultAssistant(l10n));
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
    _assistants.add(Assistant(
      id: const Uuid().v4(),
      name: l10n.assistantProviderOcrAssistantName,
      systemPrompt: _defaultOcrPrompt,
      deletable: false,
      temperature: 0.6,
      topP: 1.0,
    ));
    await _persist();
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

    final prev = _assistants[idx];
    final raw = (updated.avatar ?? '').trim();
    final prevRaw = (prev.avatar ?? '').trim();
    if (raw != prevRaw && raw.startsWith('http')) {
      try {
        await AvatarCache.getPath(raw);
      } catch (_) {}
    }

    _assistants[idx] = updated;
    await _persist();
    notifyListeners();
  }

  static Future<String?> resolveToAbsolutePath(String path) async {
    if (path.isEmpty) return null;
    // Web: keep as-is for http(s)/data URLs; other values are not readable.
    if (path.startsWith('http') || path.startsWith('data:')) return path;
    return null;
  }

  Future<void> deleteAssistant(String id) async {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    if (!_assistants[idx].deletable) return;
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
    notifyListeners();
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

  Future<void> reorderAssistantRegex({
    required String assistantId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final idx = _assistants.indexWhere((a) => a.id == assistantId);
    if (idx == -1) return;

    final rules = List<AssistantRegex>.of(_assistants[idx].regexRules);
    if (oldIndex < 0 || oldIndex >= rules.length) return;
    if (newIndex < 0 || newIndex >= rules.length) return;

    final item = rules.removeAt(oldIndex);
    rules.insert(newIndex, item);

    _assistants[idx] = _assistants[idx].copyWith(regexRules: rules);
    notifyListeners();
    await _persist();
  }

  // Export all assistants as JSON-compatible list
  List<Map<String, dynamic>> exportAssistants() {
    return _assistants.map((a) => a.toJson()).toList();
  }

  // Import assistants (merge strategy: overwrite if ID exists, else add)
  Future<void> importAssistants(List<Map<String, dynamic>> data) async {
    int added = 0;
    int updated = 0;
    
    for (final json in data) {
      try {
        final a = Assistant.fromJson(json);
        final idx = _assistants.indexWhere((existing) => existing.id == a.id);
        if (idx != -1) {
          _assistants[idx] = a;
          updated++;
        } else {
          _assistants.add(a);
          added++;
        }
      } catch (e) {
        if (kDebugMode) {
          print('[AssistantProvider] Import skip invalid item: $e');
        }
      }
    }
    
    if (added > 0 || updated > 0) {
      await _persist();
      notifyListeners();
    }
  }
}

