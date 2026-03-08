class HeatmapApiConfig {
  const HeatmapApiConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    this.requestTimeoutSeconds = 15,
  });

  static const String defaultSupabaseUrl =
      'https://ialgqpzyysctbtqrwyqq.supabase.co';
  static const String defaultPublishableKey =
      'sb_publishable_tBWvZfUGmzEP9BJWcZCKMA_wFIXV6N1';

  final String supabaseUrl;
  final String publishableKey;
  final int requestTimeoutSeconds;

  factory HeatmapApiConfig.fromEnvironment() {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const anonKeyFallback = String.fromEnvironment('SUPABASE_ANON_KEY');

    final resolvedPublishableKey =
        publishableKey.isNotEmpty ? publishableKey : anonKeyFallback;
    final resolvedSupabaseUrl =
        supabaseUrl.trim().isEmpty ? defaultSupabaseUrl : supabaseUrl;
    final resolvedPublicKey = resolvedPublishableKey.trim().isEmpty
        ? defaultPublishableKey
        : resolvedPublishableKey;

    return HeatmapApiConfig(
      supabaseUrl: _normalizeBaseUrl(resolvedSupabaseUrl),
      publishableKey: resolvedPublicKey.trim(),
    );
  }

  bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      publishableKey.isNotEmpty &&
      Uri.tryParse(supabaseUrl) != null;

  String? get validationError {
    if (supabaseUrl.isEmpty) {
      return 'SUPABASE_URL이 비어 있습니다.';
    }

    if (publishableKey.isEmpty) {
      return 'SUPABASE_PUBLISHABLE_KEY 또는 SUPABASE_ANON_KEY가 필요합니다.';
    }

    return null;
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}
