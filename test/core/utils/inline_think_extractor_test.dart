import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/core/utils/inline_think_extractor.dart';

void main() {
  group('extractInlineThink', () {
    test('returns original content when no <think> tags', () {
      final r = extractInlineThink('hello');
      expect(r.reasoning, '');
      expect(r.content, 'hello');
    });

    test('extracts single <think> block and strips it from content', () {
      final r = extractInlineThink('<think>abc</think>answer');
      expect(r.reasoning, 'abc');
      expect(r.content, 'answer');
    });

    test('concatenates multiple <think> blocks', () {
      final r = extractInlineThink('a<think>t1</think>b<think>t2</think>c');
      expect(r.reasoning, 't1\n\nt2');
      expect(r.content, 'abc');
    });

    test('treats unclosed <think> block as running to end', () {
      final r = extractInlineThink('x<think>t');
      expect(r.reasoning, 't');
      expect(r.content, 'x');
    });
  });
}

