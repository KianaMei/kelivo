import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class JinaSearchService extends SearchService<JinaOptions> {
  @override
  String get name => 'Jina';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderJinaDescription, style: const TextStyle(fontSize: 12));
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required JinaOptions serviceOptions,
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
          'q': query,
        });

        final response = await http
            .post(
              Uri.parse('https://s.jina.ai/'),
              headers: {
                'Authorization': 'Bearer ${keyConfig.key}',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                // Speed up and reduce payload: omit page content in response
                // 'X-Respond-With': 'no-content',
                // Some gateways behave better with a standard UA
                // 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              },
              body: body,
            )
            .timeout(Duration(milliseconds: commonOptions.timeout < 15000 ? 15000 : commonOptions.timeout));

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

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Jina typically returns { data: [...] }. Be permissive in case of variant shapes.
        final listRaw = (data['data'] ?? data['results'] ?? const <dynamic>[]) as List;
        final list = listRaw;
        final results = list.take(commonOptions.resultSize).map((item) {
          final m = (item as Map).cast<String, dynamic>();
          return SearchResultItem(
            title: (m['title'] ?? '').toString(),
            url: (m['url'] ?? '').toString(),
            text: (m['description'] ?? '').toString(),
          );
        }).toList();

        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Jina search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}
