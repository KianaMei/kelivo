/// Utilities for handling Gemini 3 `thoughtSignature` metadata persisted as
/// HTML comments in message content.
///
/// We store the metadata out-of-band (e.g., Hive box) and strip it from UI text,
/// but we still need to be able to extract/append it when talking to Gemini.
class GeminiThoughtSignatures {
  GeminiThoughtSignatures._();

  static const String tag = 'gemini_thought_signatures';

  /// Matches a full signature comment:
  /// `<!-- gemini_thought_signatures:{...} -->`
  ///
  /// Note: This intentionally does NOT include the leading newline that some
  /// producers may prepend.
  static final RegExp commentRe = RegExp(
    r'<!--\s*gemini_thought_signatures:.*?-->',
    dotAll: true,
  );

  static bool hasAny(String input) => input.contains(tag) && commentRe.hasMatch(input);

  /// Extracts the last signature comment from [input].
  /// Returns the full `<!-- ... -->` comment (without any leading newline).
  static String? extractLast(String input) {
    if (input.isEmpty) return null;
    final matches = commentRe.allMatches(input);
    Match? last;
    for (final m in matches) {
      last = m;
    }
    return last?.group(0);
  }

  /// Removes all signature comments from [input].
  ///
  /// Important: We do NOT trim here to avoid breaking whitespace/tokenization
  /// across streaming chunk boundaries.
  static String stripAll(String input) {
    if (!hasAny(input)) return input;
    return input.replaceAll(commentRe, '');
  }
}

