/// Inline <think> tag extractor.
///
/// Some reasoning models emit vendor-style inline thinking blocks:
/// `<think>...</think>` (or until end of text).
///
/// This helper extracts all thinking blocks and returns:
/// - `reasoning`: concatenated thinking text (separated by blank lines)
/// - `content`: the remaining visible content with all thinking blocks removed

final RegExp inlineThinkRegex = RegExp(
  r"<think>([\s\S]*?)(?:</think>|$)",
  dotAll: true,
);

({String content, String reasoning}) extractInlineThink(String raw) {
  final extractedThinking = inlineThinkRegex
      .allMatches(raw)
      .map((m) => (m.group(1) ?? '').trim())
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  if (extractedThinking.isEmpty) return (content: raw, reasoning: '');

  final contentWithoutThink = raw.replaceAll(inlineThinkRegex, '').trim();
  return (content: contentWithoutThink, reasoning: extractedThinking);
}

