import 'dart:math';
import 'package:flutter_test/flutter_test.dart' hide expect, group;
import 'package:glados/glados.dart';
import 'package:kelivo/core/models/tool_call_mode.dart';
import 'package:kelivo/core/services/prompt_tool_use/xml_tag_extractor.dart';

/// Custom generators for property-based testing
extension CustomAny on Any {
  /// Generate valid tool names (alphanumeric with underscores, non-empty)
  static Generator<String> toolName = any.letterOrDigits
      .map((s) => s.isEmpty ? 'tool' : s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), 'x'));
  
  /// Generate safe string values (no special chars that break JSON)
  static Generator<String> safeString = any.letterOrDigits;
  
  /// Generate positive integers for arguments
  static Generator<int> positiveInt = any.positiveIntOrZero;
}

void main() {
  group('XmlTagExtractor Property Tests', () {
    // **Feature: prompt-tool-use, Property 1: XML 解析往返一致性**
    // **Validates: Requirements 3.6**
    Glados2(CustomAny.toolName, any.int).test(
      'Property 1: XML parsing round-trip consistency',
      (toolName, argValue) {
        // Ensure toolName is not empty
        final name = toolName.isEmpty ? 'test_tool' : toolName;
        
        // Create original ParsedToolUse with simple integer argument
        final args = <String, dynamic>{'value': argValue};
        final original = ParsedToolUse.create(name: name, arguments: args);
        
        // Convert to XML
        final xml = original.toXml();
        
        // Parse back
        final parsed = XmlTagExtractor.parseToolUse(xml);
        
        // Verify round-trip (ignoring id since it contains timestamp)
        expect(parsed, isNotNull, reason: 'Parsed result should not be null for xml: $xml');
        expect(parsed!.name, equals(original.name), 
            reason: 'Name should match after round-trip');
        expect(original.equalsIgnoringId(parsed), isTrue,
            reason: 'ParsedToolUse should be equivalent after round-trip (ignoring id)');
      },
    );

    // **Feature: prompt-tool-use, Property 2: 流式 chunk 分割不影响解析结果**
    // **Validates: Requirements 3.2**
    // Using 5 separate int generators to simulate split positions
    Glados(any.positiveIntOrZero).test(
      'Property 2: Streaming chunk splitting does not affect parsing result',
      (splitSeed) {
        final toolName = 'get_sticker';
        final argValue = splitSeed % 100;
        
        // Generate split positions from seed
        final random = Random(splitSeed);
        final splitOffsets = List.generate(5, (_) => random.nextInt(100));
        
        // Create a complete XML string with tool_use tag
        final fullText = 'Hello <tool_use>\n  <name>$toolName</name>\n  <arguments>{"value": $argValue}</arguments>\n</tool_use> World';
        
        // Process as single chunk
        final singleExtractor = XmlTagExtractor();
        final singleResults = singleExtractor.processChunk(fullText);
        
        // Collect tag content from single chunk processing
        final singleTagContent = singleResults
            .where((r) => r.isTagContent)
            .map((r) => r.content)
            .join();
        
        // Process as multiple chunks based on split positions
        final multiExtractor = XmlTagExtractor();
        final multiResults = <TagExtractionResult>[];
        
        // Normalize split positions to be within text bounds and unique
        final normalizedSplits = splitOffsets
            .map((p) => fullText.isEmpty ? 0 : (p % max(1, fullText.length - 1)) + 1)
            .where((p) => p > 0 && p < fullText.length)
            .toSet()
            .toList()
          ..sort();
        
        // Split text and process each chunk
        var lastPos = 0;
        for (final pos in normalizedSplits) {
          final intPos = pos as int;
          if (intPos > lastPos) {
            multiResults.addAll(multiExtractor.processChunk(
              fullText.substring(lastPos, intPos),
            ));
            lastPos = intPos;
          }
        }
        if (lastPos < fullText.length) {
          multiResults.addAll(multiExtractor.processChunk(
            fullText.substring(lastPos),
          ));
        }
        
        // Collect tag content from multi-chunk processing
        final multiTagContent = multiResults
            .where((r) => r.isTagContent)
            .map((r) => r.content)
            .join();
        
        // Both should extract the same tag content
        expect(multiTagContent, equals(singleTagContent),
            reason: 'Tag content should be the same regardless of chunk splitting');
      },
    );

    // **Feature: prompt-tool-use, Property 3: 标签过滤完整性**
    // **Validates: Requirements 3.3**
    Glados3(
      CustomAny.safeString,
      CustomAny.toolName,
      CustomAny.safeString,
    ).test(
      'Property 3: Tag filtering completeness',
      (prefix, toolName, suffix) {
        // Ensure toolName is not empty
        final name = toolName.isEmpty ? 'test_tool' : toolName;
        
        // Create text with tool_use tag
        final fullText = '$prefix<tool_use>\n  <name>$name</name>\n  <arguments>{}</arguments>\n</tool_use>$suffix';
        
        // Process the text
        final extractor = XmlTagExtractor();
        final results = extractor.processChunk(fullText);
        
        // Collect non-tag content
        final nonTagContent = results
            .where((r) => !r.isTagContent)
            .map((r) => r.content)
            .join();
        
        // Non-tag content should not contain tool_use tags
        expect(nonTagContent.contains('<tool_use>'), isFalse,
            reason: 'Non-tag content should not contain <tool_use>');
        expect(nonTagContent.contains('</tool_use>'), isFalse,
            reason: 'Non-tag content should not contain </tool_use>');
      },
    );
  });
}
