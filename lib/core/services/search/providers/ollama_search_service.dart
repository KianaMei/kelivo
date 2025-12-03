import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';
import '../../http/dio_client.dart';

class OllamaSearchService extends SearchService<OllamaOptions> {
  @override
  String get name => 'Ollama';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderOllamaDescription, style: const TextStyle(fontSize: 12));
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required OllamaOptions serviceOptions,
  }) async {
    Exception? lastError;
    final tried = <String>{};
    final maxAttempts = serviceOptions.apiKeys.length;
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      final keyConfig = serviceOptions.getNextAvailableKey(excludeIds: tried);
      if (keyConfig == null) break;
      tried.add(keyConfig.id);
      attempts++;
      
      try {
        final body = jsonEncode({
          'query': query,
          'max_results': commonOptions.resultSize.clamp(1, 10),
        });

        final response = await simpleDio.post(
          'https://ollama.com/api/web_search',
          data: jsonDecode(body),
          options: Options(
            headers: {
              'Authorization': 'Bearer ${keyConfig.key}',
              'Content-Type': 'application/json',
            },
            receiveTimeout: Duration(milliseconds: commonOptions.timeout),
            validateStatus: (status) => true,
          ),
        );

        if (response.statusCode == 429) {
          serviceOptions.markKeyRateLimited(keyConfig.id, error: 'http_429');
          lastError = Exception('Rate limit reached for key: ${keyConfig.name ?? keyConfig.id}');
          continue;
        }

        if (response.statusCode != 200) {
          serviceOptions.markKeyFailure(keyConfig.id, error: 'http_${response.statusCode}');
          lastError = Exception('API request failed: ${response.statusCode}');
          continue;
        }

        final data = (response.data is String ? jsonDecode(response.data) : response.data) as Map<String, dynamic>;
        final list = (data['results'] as List? ?? const []);
        final results = list.map((item) {
          final map = item as Map<String, dynamic>;
          return SearchResultItem(
            title: (map['title'] ?? '').toString(),
            url: (map['url'] ?? '').toString(),
            text: (map['content'] ?? '').toString(),
          );
        }).toList();

        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Ollama search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}

