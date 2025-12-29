import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/api_key_runtime_state.dart';
import '../api_key_manager.dart';
import '../../../utils/sandbox_path_resolver.dart';

class ChatService extends ChangeNotifier {
  static const String _conversationsBoxName = 'conversations';
  static const String _messagesBoxName = 'messages';
  static const String _toolEventsBoxName = 'tool_events_v1';
  static const String _geminiThoughtSigsBoxName = 'gemini_thought_sigs_v1';

  late Box<Conversation> _conversationsBox;
  late Box<ChatMessage> _messagesBox;
  late Box
  _toolEventsBox; // key: assistantMessageId, value: List<Map<String,dynamic>>
  late Box<String> _geminiThoughtSigsBox; // key: messageId, value: "<!-- gemini_thought_signatures:... -->"

  String? _currentConversationId;
  final Map<String, List<ChatMessage>> _messagesCache = {};
  final Map<String, Conversation> _draftConversations = {};

  // Localized default title for new conversations; set by UI on startup.
  String _defaultConversationTitle = 'New Chat';
  void setDefaultConversationTitle(String title) {
    if (title.trim().isEmpty) return;
    _defaultConversationTitle = title.trim();
  }

  bool _initialized = false;
  bool get initialized => _initialized;

  String? get currentConversationId => _currentConversationId;

  Future<void> init() async {
    if (_initialized) return;

    // Web: Hive uses IndexedDB (hive_flutter)
    await Hive.initFlutter();
    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ConversationAdapter());
    }

    _conversationsBox = await Hive.openBox<Conversation>(_conversationsBoxName);
    _messagesBox = await Hive.openBox<ChatMessage>(_messagesBoxName);
    _toolEventsBox = await Hive.openBox(_toolEventsBoxName);
    _geminiThoughtSigsBox = await Hive.openBox<String>(_geminiThoughtSigsBoxName);

    // Initialize ApiKeyManager (registers adapter and opens box)
    await ApiKeyManager().init();

    // Migrate API key runtime states from old ProviderConfig JSON
    await _migrateApiKeyStates();

    // Migrate any persisted message content that references old iOS sandbox paths
    await _migrateSandboxPaths();

    _initialized = true;
    notifyListeners();
  }

  List<Conversation> getAllConversations() {
    if (!_initialized) return [];
    final conversations = _conversationsBox.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  List<Conversation> getPinnedConversations() {
    return getAllConversations().where((c) => c.isPinned).toList();
  }

  Conversation? getConversation(String id) {
    if (!_initialized) return null;
    return _conversationsBox.get(id) ?? _draftConversations[id];
  }

  List<ChatMessage> getMessages(String conversationId) {
    if (!_initialized) return [];

    // Check cache first
    if (_messagesCache.containsKey(conversationId)) {
      return _messagesCache[conversationId]!;
    }

    // Load from storage - check both persisted and draft conversations
    final conversation =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (conversation == null) return [];

    final messages = <ChatMessage>[];
    for (final messageId in conversation.messageIds) {
      final message = _messagesBox.get(messageId);
      if (message != null) {
        messages.add(message);
      }
    }

    // Cache the result
    _messagesCache[conversationId] = messages;
    return messages;
  }

  /// Force refresh messages from database, bypassing cache AND conversation.messageIds.
  /// This directly queries _messagesBox by conversationId to ensure ALL messages are returned,
  /// even if conversation.messageIds is out of sync (which can happen due to Hive caching).
  /// Use this when you need guaranteed fresh data (e.g., for title generation).
  List<ChatMessage> getMessagesFresh(String conversationId) {
    if (!_initialized) return [];

    // Clear cache
    _messagesCache.remove(conversationId);

    // CRITICAL: Bypass conversation.messageIds entirely!
    // Query _messagesBox directly by conversationId to ensure we get ALL messages.
    // This fixes issues where Hive's in-memory conversation object has stale messageIds.
    final messages =
        _messagesBox.values
            .where((m) => m.conversationId == conversationId)
            .toList();

    // Sort by timestamp to maintain chronological order
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Update cache with fresh data
    _messagesCache[conversationId] = messages;
    return messages;
  }

  Future<Conversation> createConversation({
    String? title,
    String? assistantId,
  }) async {
    if (!_initialized) await init();

    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );

    await _conversationsBox.put(conversation.id, conversation);
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  // Create a draft conversation that is not persisted until first message arrives.
  Future<Conversation> createDraftConversation({
    String? title,
    String? assistantId,
  }) async {
    if (!_initialized) await init();
    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );
    _draftConversations[conversation.id] = conversation;
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  Future<void> deleteConversation(String id) async {
    if (!_initialized) return;

    // If it's a draft and never persisted, just drop it.
    if (_draftConversations.containsKey(id)) {
      _draftConversations.remove(id);
      if (_currentConversationId == id) {
        _currentConversationId = null;
      }
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    // Collect local file paths referenced by messages in this conversation
    final Set<String> pathsToMaybeDelete = <String>{};
    for (final messageId in conversation.messageIds) {
      final message = _messagesBox.get(messageId);
      if (message == null) continue;
      final content = message.content;
      // [image:/abs/path]
      final imgRe = RegExp(r"\[image:(.+?)\]");
      for (final m in imgRe.allMatches(content)) {
        final pth = m.group(1)?.trim();
        if (pth != null &&
            pth.isNotEmpty &&
            !pth.startsWith('http') &&
            !pth.startsWith('data:')) {
          pathsToMaybeDelete.add(pth);
        }
      }
      // [file:/abs/path|filename|mime]
      final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
      for (final m in fileRe.allMatches(content)) {
        final pth = m.group(1)?.trim();
        if (pth != null &&
            pth.isNotEmpty &&
            !pth.startsWith('http') &&
            !pth.startsWith('data:')) {
          pathsToMaybeDelete.add(pth);
        }
      }
    }

    // Delete all messages
    for (final messageId in conversation.messageIds) {
      final msg = _messagesBox.get(messageId);
      if (msg != null && msg.role == 'assistant') {
        try {
          await _toolEventsBox.delete(msg.id);
        } catch (_) {}
      }
      try {
        await _geminiThoughtSigsBox.delete(messageId);
      } catch (_) {}
      await _messagesBox.delete(messageId);
    }

    // Delete conversation
    await _conversationsBox.delete(id);

    // Remove cached messages
    // Clear cache
    _messagesCache.remove(id);

    // Delete orphaned files (not referenced by any remaining conversation)
    await _cleanupOrphanUploads();

    if (_currentConversationId == id) {
      _currentConversationId = null;
    }

    notifyListeners();
  }

  Set<String> _extractAttachmentPaths(String content) {
    final out = <String>{};
    final imgRe = RegExp(r"\[image:(.+?)\]");
    for (final m in imgRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    for (final m in fileRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    return out;
  }

  /// Migrate API key runtime states from old ProviderConfig JSON to Hive
  /// This is a one-time migration for users upgrading from the old schema
  Future<void> _migrateApiKeyStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'provider_configs'; // SettingsProvider._providerConfigsKey

      // Check if migration already done
      final migrated = prefs.getBool('api_key_states_migrated') ?? false;
      if (migrated) return;

      // Read old provider configs
      final json = prefs.getString(key);
      if (json == null || json.isEmpty) {
        // No old data to migrate
        await prefs.setBool('api_key_states_migrated', true);
        return;
      }

      final data = jsonDecode(json) as Map<String, dynamic>;
      int migratedCount = 0;

      for (final providerEntry in data.entries) {
        final providerConfig = providerEntry.value as Map<String, dynamic>?;
        if (providerConfig == null) continue;

        final apiKeys = providerConfig['apiKeys'] as List?;
        if (apiKeys == null || apiKeys.isEmpty) continue;

        for (final keyJson in apiKeys) {
          if (keyJson is! Map<String, dynamic>) continue;

          final keyId = keyJson['id'] as String?;
          if (keyId == null) continue;

          // Extract old runtime fields
          final usage = keyJson['usage'] as Map<String, dynamic>?;
          final statusStr = (keyJson['status'] as String?) ?? 'active';
          final lastError = keyJson['lastError'] as String?;
          final updatedAt =
              (keyJson['updatedAt'] as int?) ??
              DateTime.now().millisecondsSinceEpoch;

          // Create runtime state from old data
          final state = ApiKeyRuntimeState(
            keyId: keyId,
            totalRequests: (usage?['totalRequests'] as int?) ?? 0,
            successfulRequests: (usage?['successfulRequests'] as int?) ?? 0,
            failedRequests: (usage?['failedRequests'] as int?) ?? 0,
            consecutiveFailures: (usage?['consecutiveFailures'] as int?) ?? 0,
            lastUsed: usage?['lastUsed'] as int?,
            status: statusStr,
            lastError: lastError,
            updatedAt: updatedAt,
          );

          // Save to Hive (only if not already exists)
          final existing = ApiKeyManager().getKeyState(keyId);
          if (existing == null) {
            await ApiKeyManager().updateKeyStatus(
              keyId,
              true, // Mark as active to avoid immediate error state
              maxFailuresBeforeDisable: 3,
            );
            // Then overwrite with migrated data
            final box = Hive.box<ApiKeyRuntimeState>('api_key_states');
            await box.put(keyId, state);
            migratedCount++;
          }
        }
      }

      // Mark migration as complete
      await prefs.setBool('api_key_states_migrated', true);

      if (kDebugMode && migratedCount > 0) {
        print(
          '[ChatService] Migrated $migratedCount API key runtime states to Hive',
        );
      }
    } catch (e) {
      // Log error but don't block initialization
      if (kDebugMode) {
        print('[ChatService] API key state migration failed: $e');
      }
    }
  }

  Future<void> _migrateSandboxPaths() async {
    try {
      // No-op if empty
      if (_messagesBox.isEmpty) return;
      final imgRe = RegExp(r"\[image:(.+?)\]");
      final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");

      for (final key in _messagesBox.keys) {
        final msg = _messagesBox.get(key);
        if (msg == null) continue;
        final content = msg.content;
        String updated = content;
        bool changed = false;

        // Rewrite image paths
        updated = updated.replaceAllMapped(imgRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[image:$fixed]';
        });

        // Rewrite file attachment paths
        updated = updated.replaceAllMapped(fileRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final name = (m.group(2) ?? '').trim();
          final mime = (m.group(3) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[file:$fixed|$name|$mime]';
        });

        if (changed && updated != content) {
          final newMsg = msg.copyWith(content: updated);
          await _messagesBox.put(msg.id, newMsg);
        }
      }
    } catch (_) {
      // best-effort migration; ignore errors
    }
  }

  Future<void> _cleanupOrphanUploads() async {
    // Web: uploads live on the server; no local file cleanup here.
  }

  Future<void> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    if (!_initialized) await init();
    // Restore messages first
    for (final m in messages) {
      await _messagesBox.put(m.id, m);
    }
    // Ensure messageIds are in the same order
    final ids = messages.map((m) => m.id).toList();
    final restored = Conversation(
      id: conversation.id,
      title: conversation.title,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      messageIds: ids,
      isPinned: conversation.isPinned,
      mcpServerIds: List.of(conversation.mcpServerIds),
      truncateIndex: conversation.truncateIndex,
      assistantId: conversation.assistantId,
      versionSelections: Map<String, int>.from(conversation.versionSelections),
    );
    await _conversationsBox.put(restored.id, restored);

    // Update caches
    _messagesCache[restored.id] = List.of(messages);

    notifyListeners();
  }

  // Add a message directly to an existing conversation (for merge mode)
  Future<void> addMessageDirectly(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!_initialized) await init();

    // Add message to box
    await _messagesBox.put(message.id, message);

    // Update conversation
    final conversation = _conversationsBox.get(conversationId);
    if (conversation != null) {
      if (!conversation.messageIds.contains(message.id)) {
        conversation.messageIds.add(message.id);
        // Keep original updatedAt during restore
        await conversation.save();
      }
    }

    // Update cache
    if (_messagesCache.containsKey(conversationId)) {
      if (!_messagesCache[conversationId]!.any((m) => m.id == message.id)) {
        _messagesCache[conversationId]!.add(message);
      }
    }

    notifyListeners();
  }

  // Conversation-scoped MCP servers selection
  List<String> getConversationMcpServers(String conversationId) {
    if (!_initialized) return const <String>[];
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return c?.mcpServerIds ?? const <String>[];
  }

  Future<void> setConversationMcpServers(
    String conversationId,
    List<String> serverIds,
  ) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.mcpServerIds = List.of(serverIds);
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.mcpServerIds = List.of(serverIds);
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<void> toggleConversationMcpServer(
    String conversationId,
    String serverId,
    bool enabled,
  ) async {
    final current = getConversationMcpServers(conversationId);
    final set = current.toSet();
    if (enabled) {
      set.add(serverId);
    } else {
      set.remove(serverId);
    }
    await setConversationMcpServers(conversationId, set.toList());
  }

  Future<void> renameConversation(String id, String newTitle) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.title = newTitle;
      // Don't update updatedAt - renaming shouldn't affect sort order
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    conversation.title = newTitle;
    // Don't update updatedAt - renaming shouldn't affect sort order
    await conversation.save();
    notifyListeners();
  }

  /// Update the summary and lastSummarizedMessageCount for a conversation.
  /// Used for LLM-generated summaries for the recent chats reference feature.
  Future<void> updateConversationSummary(
    String id,
    String summary,
    int messageCount,
  ) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      // Draft conversations don't need summaries yet
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    // Use HiveObject's direct field access since summary and lastSummarizedMessageCount are mutable
    // We need to create a new object since HiveField are final for some fields
    final updated = conversation.copyWith(
      summary: summary,
      lastSummarizedMessageCount: messageCount,
    );
    // Delete old and save new (Hive workaround for non-trivial updates)
    await _conversationsBox.put(id, updated);
    notifyListeners();
  }

  /// Get all conversations with a summary for a specific assistant.
  /// Used for displaying and managing summaries in the memory tab.
  List<Conversation> getConversationsWithSummaryForAssistant(
    String? assistantId,
  ) {
    if (!_initialized) return [];
    return _conversationsBox.values
        .where(
          (c) =>
              c.assistantId == assistantId &&
              c.summary != null &&
              c.summary!.trim().isNotEmpty,
        )
        .toList()
      ..sort(
        (a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(
          a.updatedAt ?? DateTime(1970),
        ),
      );
  }

  /// Clear the summary for a specific conversation.
  Future<void> clearConversationSummary(String id) async {
    if (!_initialized) return;
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    final updated = conversation.copyWith(
      summary: '',
      lastSummarizedMessageCount: 0,
    );
    await _conversationsBox.put(id, updated);
    notifyListeners();
  }

  Future<void> togglePinConversation(String id) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.isPinned = !draft.isPinned;
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    conversation.isPinned = !conversation.isPinned;
    await conversation.save();
    notifyListeners();
  }

  Future<ChatMessage> addMessage({
    required String conversationId,
    required String role,
    required String content,
    String? modelId,
    String? providerId,
    int? totalTokens,
    String? tokenUsageJson,
    bool isStreaming = false,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? groupId,
    int? version,
  }) async {
    if (!_initialized) await init();

    var conversation = _conversationsBox.get(conversationId);
    // If conversation doesn't exist yet, persist draft (if any)
    if (conversation == null) {
      final draft = _draftConversations.remove(conversationId);
      if (draft != null) {
        await _conversationsBox.put(draft.id, draft);
        conversation = draft;
      } else {
        // Create a new one on the fly as a fallback
        conversation = Conversation(
          id: conversationId,
          title: _defaultConversationTitle,
        );
        await _conversationsBox.put(conversationId, conversation);
      }
    }

    final message = ChatMessage(
      role: role,
      content: content,
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerId,
      totalTokens: totalTokens,
      tokenUsageJson: tokenUsageJson,
      isStreaming: isStreaming,
      reasoningText: reasoningText,
      reasoningStartAt: reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt,
      groupId: groupId,
      version: version,
    );

    await _messagesBox.put(message.id, message);

    conversation.messageIds.add(message.id);
    conversation.updatedAt = DateTime.now();
    await conversation.save();

    // Update cache
    if (_messagesCache.containsKey(conversationId)) {
      _messagesCache[conversationId]!.add(message);
    }

    notifyListeners();
    return message;
  }

  Future<void> updateMessage(
    String messageId, {
    String? content,
    int? totalTokens,
    String? tokenUsageJson,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
  }) async {
    if (!_initialized) return;

    final message = _messagesBox.get(messageId);
    if (message == null) return;

    final updatedMessage = message.copyWith(
      content: content ?? message.content,
      totalTokens: totalTokens ?? message.totalTokens,
      tokenUsageJson: tokenUsageJson ?? message.tokenUsageJson,
      isStreaming: isStreaming ?? message.isStreaming,
      reasoningText: reasoningText ?? message.reasoningText,
      reasoningStartAt: reasoningStartAt ?? message.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? message.reasoningFinishedAt,
      translation: translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? message.reasoningSegmentsJson,
    );

    await _messagesBox.put(messageId, updatedMessage);

    // Update cache
    final conversationId = message.conversationId;
    if (_messagesCache.containsKey(conversationId)) {
      final messages = _messagesCache[conversationId]!;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
      }
    }

    notifyListeners();
  }

  // Tool events persistence (per assistant message)
  List<Map<String, dynamic>> getToolEvents(String assistantMessageId) {
    if (!_initialized) return const <Map<String, dynamic>>[];
    final v = _toolEventsBox.get(assistantMessageId);
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> setToolEvents(
    String assistantMessageId,
    List<Map<String, dynamic>> events,
  ) async {
    if (!_initialized) await init();
    await _toolEventsBox.put(assistantMessageId, events);
    notifyListeners();
  }

  Future<void> upsertToolEvent(
    String assistantMessageId, {
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
    String? content,
  }) async {
    if (!_initialized) await init();
    final list = List<Map<String, dynamic>>.of(
      getToolEvents(assistantMessageId),
    );
    final cleanId = (id).toString();

    int idx = -1;
    // Prefer matching by a non-empty id
    if (cleanId.isNotEmpty) {
      idx = list.indexWhere((e) => (e['id']?.toString() ?? '') == cleanId);
    }
    // If no id or not found, match the first placeholder (no content) with same name
    if (idx < 0) {
      idx = list.indexWhere(
        (e) =>
            (e['name']?.toString() ?? '') == name &&
            (e['content'] == null ||
                (e['content']?.toString().isEmpty ?? true)),
      );
    }

    final record = <String, dynamic>{
      'id': cleanId,
      'name': name,
      'arguments': arguments,
      'content': content,
    };
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.add(record);
    }
    await _toolEventsBox.put(assistantMessageId, list);
    notifyListeners();
  }

  Future<Conversation> forkConversation({
    required String title,
    required String? assistantId,
    required List<ChatMessage> sourceMessages,
    Map<String, int>? versionSelections,
  }) async {
    if (!_initialized) await init();
    // Create new conversation first
    final convo = await createConversation(
      title: title,
      assistantId: assistantId,
    );
    final ids = <String>[];
    for (final src in sourceMessages) {
      final clone = ChatMessage(
        role: src.role,
        content: src.content,
        timestamp: src.timestamp,
        modelId: src.modelId,
        providerId: src.providerId,
        totalTokens: src.totalTokens,
        tokenUsageJson: src.tokenUsageJson,
        conversationId: convo.id,
        isStreaming: false,
        reasoningText: src.reasoningText,
        reasoningStartAt: src.reasoningStartAt,
        reasoningFinishedAt: src.reasoningFinishedAt,
        translation: src.translation,
        reasoningSegmentsJson: src.reasoningSegmentsJson,
        groupId: src.groupId,
        version: src.version,
      );
      await _messagesBox.put(clone.id, clone);
      ids.add(clone.id);
    }
    // Attach to conversation in storage
    final c = _conversationsBox.get(convo.id);
    if (c != null) {
      c.messageIds
        ..clear()
        ..addAll(ids);
      c.versionSelections = Map<String, int>.from(
        versionSelections ?? const <String, int>{},
      );
      c.updatedAt = DateTime.now();
      await c.save();
    }
    // Cache
    _messagesCache[convo.id] = [for (final id in ids) _messagesBox.get(id)!];
    notifyListeners();
    return _conversationsBox.get(convo.id)!;
  }

  Future<ChatMessage?> appendMessageVersion({
    required String messageId,
    required String content,
  }) async {
    if (!_initialized) await init();
    final original = _messagesBox.get(messageId);
    if (original == null) return null;

    final cid = original.conversationId;
    final convo = _conversationsBox.get(cid) ?? _draftConversations[cid];
    if (convo == null) return null;

    final gid = (original.groupId ?? original.id);
    // Find current max version within this group in this conversation
    int maxVersion = -1;
    for (final mid in convo.messageIds) {
      final m = _messagesBox.get(mid);
      if (m == null) continue;
      final mg = (m.groupId ?? m.id);
      if (mg == gid) {
        if (m.version > maxVersion) maxVersion = m.version;
      }
    }
    final nextVersion = maxVersion + 1;

    final newMsg = ChatMessage(
      role: original.role,
      content: content,
      conversationId: cid,
      modelId: original.modelId,
      providerId: original.providerId,
      totalTokens: null,
      isStreaming: false,
      groupId: gid,
      version: nextVersion,
    );
    await _messagesBox.put(newMsg.id, newMsg);
    // Append to conversation order at the end (we'll group when rendering)
    if (_draftConversations.containsKey(cid)) {
      final draft = _draftConversations[cid]!;
      draft.messageIds.add(newMsg.id);
      draft.updatedAt = DateTime.now();
      draft.versionSelections[gid] = nextVersion;
    } else {
      final c = _conversationsBox.get(cid);
      if (c != null) {
        c.messageIds.add(newMsg.id);
        c.updatedAt = DateTime.now();
        // Persist selection of latest version for this group
        c.versionSelections[gid] = nextVersion;
        await c.save();
      }
    }
    // Update caches
    final arr = _messagesCache[cid];
    if (arr != null) arr.add(newMsg);
    notifyListeners();
    return newMsg;
  }

  Map<String, int> getVersionSelections(String conversationId) {
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return Map<String, int>.from(c?.versionSelections ?? const <String, int>{});
  }

  Future<void> setSelectedVersion(
    String conversationId,
    String groupId,
    int version,
  ) async {
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.versionSelections[groupId] = version;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.versionSelections[groupId] = version;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<Conversation?> toggleTruncateAtTail(
    String conversationId, {
    String? defaultTitle,
  }) async {
    if (!_initialized) await init();
    // Draft case
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      final lastIndexPlusOne = draft.messageIds.length; // last index + 1
      final newValue =
          (draft.truncateIndex == lastIndexPlusOne) ? -1 : lastIndexPlusOne;
      draft.truncateIndex = newValue;
      if ((defaultTitle ?? '').isNotEmpty) draft.title = defaultTitle!;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return draft;
    }
    // Persisted case
    final c = _conversationsBox.get(conversationId);
    if (c == null) return null;
    final lastIndexPlusOne = c.messageIds.length;
    final newValue =
        (c.truncateIndex == lastIndexPlusOne) ? -1 : lastIndexPlusOne;
    c.truncateIndex = newValue;
    if ((defaultTitle ?? '').isNotEmpty) c.title = defaultTitle!;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
    return c;
  }

  Future<Conversation?> setConversationThinkingBudget(
    String conversationId,
    int? thinkingBudget,
  ) async {
    if (!_initialized) await init();
    // Draft case
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.thinkingBudget = thinkingBudget;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return draft;
    }
    // Persisted case
    final c = _conversationsBox.get(conversationId);
    if (c == null) return null;
    c.thinkingBudget = thinkingBudget;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
    return c;
  }

  Future<void> deleteMessage(String messageId) async {
    if (!_initialized) return;

    final message = _messagesBox.get(messageId);
    if (message == null) return;

    final conversation = _conversationsBox.get(message.conversationId);
    if (conversation != null) {
      final gid = message.groupId ?? message.id;
      final ids = conversation.messageIds;

      // Find the earliest position of this message group before removal so we
      // can keep the group anchored when deleting one of its versions.
      int anchorIndex = -1;
      for (int i = 0; i < ids.length; i++) {
        final mid = ids[i];
        final m = _messagesBox.get(mid);
        if (m == null) continue;
        final mgid = m.groupId ?? m.id;
        if (mgid == gid) {
          anchorIndex = i;
          break;
        }
      }

      ids.remove(messageId);

      // If we removed the earliest version but other versions remain, move the
      // earliest remaining one back to the original anchor index to preserve
      // the group's relative order in the conversation.
      if (anchorIndex >= 0) {
        int? earliestRemaining;
        for (int i = 0; i < ids.length; i++) {
          final mid = ids[i];
          final m = _messagesBox.get(mid);
          if (m == null) continue;
          final mgid = m.groupId ?? m.id;
          if (mgid == gid) {
            earliestRemaining = i;
            break;
          }
        }

        if (earliestRemaining != null && earliestRemaining > anchorIndex) {
          final replacementId = ids.removeAt(earliestRemaining);
          final insertAt = anchorIndex <= ids.length ? anchorIndex : ids.length;
          ids.insert(insertAt, replacementId);
        }
      }

      await conversation.save();
    }

    await _messagesBox.delete(messageId);
    // Remove any tool events linked to this assistant message
    if (message.role == 'assistant') {
      try {
        await _toolEventsBox.delete(message.id);
      } catch (_) {}
    }
    try {
      await _geminiThoughtSigsBox.delete(messageId);
    } catch (_) {}

    // Update cache: clear this conversation so that next getMessages()
    // reloads messages in the updated order from conversation.messageIds.
    _messagesCache.remove(message.conversationId);

    // Clean up orphaned upload files that are no longer referenced by any message
    await _cleanupOrphanUploads();

    notifyListeners();
  }

  void setCurrentConversation(String? id) {
    _currentConversationId = id;
    notifyListeners();
  }

  /// Import or update a conversation from JSON (for incremental sync)
  /// Always merges messageIds (union). Metadata uses "newer wins" strategy.
  Future<void> importConversationFromJson(Map<String, dynamic> json) async {
    if (!_initialized) await init();

    final remoteConv = Conversation.fromJson(json);
    final localConv = _conversationsBox.get(remoteConv.id);

    if (localConv == null) {
      // Local doesn't exist -> save remote, but filter to only existing message IDs
      final filteredIds =
          remoteConv.messageIds
              .where((id) => _messagesBox.containsKey(id))
              .toList();
      final filtered = Conversation(
        id: remoteConv.id,
        title: remoteConv.title,
        createdAt: remoteConv.createdAt,
        updatedAt: remoteConv.updatedAt,
        messageIds: filteredIds,
        isPinned: remoteConv.isPinned,
        mcpServerIds: List.of(remoteConv.mcpServerIds),
        truncateIndex: remoteConv.truncateIndex,
        assistantId: remoteConv.assistantId,
        versionSelections: Map<String, int>.from(remoteConv.versionSelections),
        thinkingBudget: remoteConv.thinkingBudget,
        summary: remoteConv.summary,
        lastSummarizedMessageCount: remoteConv.lastSummarizedMessageCount,
      );
      await _conversationsBox.put(filtered.id, filtered);
      notifyListeners();
      return;
    }

    // Merge messageIds (union of both sides), then filter to only existing messages
    // This prevents "ghost" message IDs that don't have corresponding message content
    final candidateIds = {...localConv.messageIds, ...remoteConv.messageIds};
    final mergedIds =
        candidateIds.where((id) => _messagesBox.containsKey(id)).toList();

    // For metadata: newer updatedAt wins, but always use remote title if local is placeholder
    final useRemoteMetadata = remoteConv.updatedAt.isAfter(localConv.updatedAt);
    final isLocalPlaceholder = localConv.title == 'Synced Conversation';

    final merged = Conversation(
      id: remoteConv.id,
      title: isLocalPlaceholder ? remoteConv.title : (useRemoteMetadata ? remoteConv.title : localConv.title),
      createdAt: localConv.createdAt, // Keep original creation time
      updatedAt: useRemoteMetadata ? remoteConv.updatedAt : localConv.updatedAt,
      messageIds: mergedIds,
      isPinned: useRemoteMetadata ? remoteConv.isPinned : localConv.isPinned,
      mcpServerIds: List.of(
        useRemoteMetadata ? remoteConv.mcpServerIds : localConv.mcpServerIds,
      ),
      truncateIndex:
          useRemoteMetadata
              ? remoteConv.truncateIndex
              : localConv.truncateIndex,
      assistantId:
          useRemoteMetadata ? remoteConv.assistantId : localConv.assistantId,
      versionSelections: Map<String, int>.from(
        useRemoteMetadata
            ? remoteConv.versionSelections
            : localConv.versionSelections,
      ),
      thinkingBudget:
          useRemoteMetadata
              ? remoteConv.thinkingBudget
              : localConv.thinkingBudget,
      summary: useRemoteMetadata ? remoteConv.summary : localConv.summary,
      lastSummarizedMessageCount:
          useRemoteMetadata
              ? remoteConv.lastSummarizedMessageCount
              : localConv.lastSummarizedMessageCount,
    );

    await _conversationsBox.put(merged.id, merged);

    // Invalidate cache
    _messagesCache.remove(merged.id);

    notifyListeners();
  }

  /// Import messages from JSON list (for incremental sync)
  /// Merges with existing messages by ID (no duplicates)
  Future<void> importMessagesFromJson(
    String conversationId,
    List<Map<String, dynamic>> messagesJson,
  ) async {
    if (!_initialized) await init();

    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null) {
      // Conversation doesn't exist yet, create a placeholder
      final placeholder = Conversation(
        id: conversationId,
        title: 'Synced Conversation',
      );
      await _conversationsBox.put(conversationId, placeholder);
    }

    final existingIds = <String>{};
    final conv = _conversationsBox.get(conversationId)!;
    existingIds.addAll(conv.messageIds);

    final newIds = <String>[];

    for (final msgJson in messagesJson) {
      final msg = ChatMessage.fromJson(msgJson);

      // Only add if not already present
      if (!existingIds.contains(msg.id)) {
        await _messagesBox.put(msg.id, msg);
        newIds.add(msg.id);
        existingIds.add(msg.id);
      }
    }

    // Update conversation messageIds if we added new ones
    if (newIds.isNotEmpty) {
      conv.messageIds.addAll(newIds);
      await conv.save();

      // Invalidate cache
      _messagesCache.remove(conversationId);

      notifyListeners();
    }
  }

  Future<void> clearAllData() async {
    if (!_initialized) return;

    await _messagesBox.clear();
    await _conversationsBox.clear();
    await _toolEventsBox.clear();
    await _geminiThoughtSigsBox.clear();
    _messagesCache.clear();
    _draftConversations.clear();
    _currentConversationId = null;
    notifyListeners();
  }

  String? getGeminiThoughtSignature(String messageId) {
    if (!_initialized) return null;
    try {
      return _geminiThoughtSigsBox.get(messageId);
    } catch (_) {
      return null;
    }
  }

  Future<void> setGeminiThoughtSignature(String messageId, String? signatureComment) async {
    if (!_initialized) await init();
    try {
      final v = (signatureComment ?? '').trim();
      if (v.isEmpty) {
        await _geminiThoughtSigsBox.delete(messageId);
      } else {
        await _geminiThoughtSigsBox.put(messageId, v);
      }
    } catch (_) {}
  }

  // Uploads stats: count and total size of files under app documents/upload
  Future<UploadStats> getUploadStats() async {
    return const UploadStats(fileCount: 0, totalBytes: 0);
  }
}

class UploadStats {
  final int fileCount;
  final int totalBytes;
  const UploadStats({required this.fileCount, required this.totalBytes});
}
