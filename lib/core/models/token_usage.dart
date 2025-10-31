class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int thoughtTokens;
  final int totalTokens;
  
  // Track individual rounds for tool calling scenarios
  // Each round: {promptTokens, completionTokens, cachedTokens, thoughtTokens}
  final List<Map<String, int>>? rounds;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cachedTokens = 0,
    this.thoughtTokens = 0,
    this.totalTokens = 0,
    this.rounds,
  });

  TokenUsage merge(TokenUsage other) {
    // For multiple API calls (e.g., tool calling rounds):
    // Track each round separately for detailed breakdown
    final newRounds = List<Map<String, int>>.from(rounds ?? []);

    // Only add a new round if other has non-zero tokens
    if (other.promptTokens > 0 || other.completionTokens > 0) {
      // If this is an update to an existing round (streaming), replace the last round
      // Otherwise, add a new round
      final shouldReplaceLastRound = newRounds.isNotEmpty &&
          other.promptTokens <= (newRounds.last['promptTokens'] ?? 0) + 100 &&
          other.completionTokens >= (newRounds.last['completionTokens'] ?? 0);

      final roundData = {
        'promptTokens': other.promptTokens,
        'completionTokens': other.completionTokens,
        'cachedTokens': other.cachedTokens,
        'thoughtTokens': other.thoughtTokens,
      };

      if (shouldReplaceLastRound) {
        newRounds[newRounds.length - 1] = roundData;
      } else if (newRounds.isEmpty ||
                 other.promptTokens != (newRounds.last['promptTokens'] ?? 0) ||
                 other.completionTokens != (newRounds.last['completionTokens'] ?? 0)) {
        newRounds.add(roundData);
      }
    }

    // Calculate totals by summing all rounds (not using cumulative API values)
    int prompt = 0;
    int completion = 0;
    int cached = 0;
    int thought = 0;

    for (final round in newRounds) {
      prompt += round['promptTokens'] ?? 0;
      completion += round['completionTokens'] ?? 0;
      cached += round['cachedTokens'] ?? 0;
      thought += round['thoughtTokens'] ?? 0;
    }

    final total = prompt + completion;

    return TokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      cachedTokens: cached,
      thoughtTokens: thought,
      totalTokens: total,
      rounds: newRounds.isEmpty ? null : newRounds,
    );
  }
}

