import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/chat/widgets/message/message_models.dart';
import 'package:kelivo/features/home/services/chat_stream_handler.dart';

void main() {
  group('ChatStreamHandler.dedupeToolPartsList', () {
    test('keeps completed result when placeholder arrives later (same id)', () {
      const id = 'call_1';
      final parts = <ToolUIPart>[
        const ToolUIPart(
          id: id,
          toolName: 'search_web',
          arguments: {'query': 'x'},
          content: '{"items":[]}',
          loading: false,
        ),
        const ToolUIPart(
          id: id,
          toolName: 'search_web',
          arguments: {'query': 'x'},
          loading: true,
        ),
      ];

      final out = ChatStreamHandler.dedupeToolPartsList(parts);
      expect(out, hasLength(1));
      expect(out.single.id, id);
      expect(out.single.loading, isFalse);
      expect(out.single.content, '{"items":[]}');
    });

    test('merges placeholder then result into completed part (same id)', () {
      const id = 'call_1';
      final parts = <ToolUIPart>[
        const ToolUIPart(
          id: id,
          toolName: 'search_web',
          arguments: {'query': 'x'},
          loading: true,
        ),
        const ToolUIPart(
          id: id,
          toolName: 'search_web',
          arguments: {'query': 'x'},
          content: '{"items":[1]}',
          loading: false,
        ),
      ];

      final out = ChatStreamHandler.dedupeToolPartsList(parts);
      expect(out, hasLength(1));
      expect(out.single.loading, isFalse);
      expect(out.single.content, '{"items":[1]}');
    });
  });

  group('ChatStreamHandler.dedupeToolEvents', () {
    test('keeps non-empty content when placeholder arrives later (same id)', () {
      const id = 'call_1';
      final events = <Map<String, dynamic>>[
        {'id': id, 'name': 'search_web', 'arguments': {'query': 'x'}, 'content': '{"items":[]}'},
        {'id': id, 'name': 'search_web', 'arguments': {'query': 'x'}, 'content': null},
      ];

      final out = ChatStreamHandler.dedupeToolEvents(events);
      expect(out, hasLength(1));
      expect(out.single['id'], id);
      expect(out.single['content'], '{"items":[]}');
    });

    test('uses latest non-empty content (same id)', () {
      const id = 'call_1';
      final events = <Map<String, dynamic>>[
        {'id': id, 'name': 'search_web', 'arguments': {'query': 'x'}, 'content': '{"items":[1]}'},
        {'id': id, 'name': 'search_web', 'arguments': {'query': 'x'}, 'content': '{"items":[2]}'},
      ];

      final out = ChatStreamHandler.dedupeToolEvents(events);
      expect(out, hasLength(1));
      expect(out.single['content'], '{"items":[2]}');
    });
  });
}

