/// Token pricing for the per-session cost meter (F-MOD-06). USD per 1M tokens.
/// Used only to estimate spend for display — actual billing is the provider's.
class ModelPrice {
  final double inputPerMTok;
  final double outputPerMTok;
  const ModelPrice(this.inputPerMTok, this.outputPerMTok);
}

class Pricing {
  /// Keyed by a substring of the model id so minor id variations still match.
  static const Map<String, ModelPrice> _table = {
    'claude-opus-4-8': ModelPrice(5, 25),
    'claude-opus-4-7': ModelPrice(5, 25),
    'claude-opus-4-6': ModelPrice(5, 25),
    'claude-sonnet-4-6': ModelPrice(3, 15),
    'claude-haiku-4-5': ModelPrice(1, 5),
    'claude-fable-5': ModelPrice(10, 50),
    // Common OpenAI-compatible analysis models, best-effort.
    'gpt-4o': ModelPrice(2.5, 10),
    'gpt-4o-mini': ModelPrice(0.15, 0.6),
  };

  static ModelPrice? priceFor(String modelId) {
    final id = modelId.toLowerCase();
    for (final entry in _table.entries) {
      if (id.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Estimated USD cost for a model + token counts, or null if the model isn't
  /// in the table (e.g. the offline demo, which has no cost).
  static double? estimateCost(String modelId, int inputTokens, int outputTokens) {
    final p = priceFor(modelId);
    if (p == null) return null;
    return inputTokens / 1e6 * p.inputPerMTok +
        outputTokens / 1e6 * p.outputPerMTok;
  }

  static String formatUsd(double usd) {
    if (usd < 0.01) return '<\$0.01';
    return '\$${usd.toStringAsFixed(usd < 1 ? 3 : 2)}';
  }
}
