import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class LinkUpSearchService extends SearchService<LinkUpOptions> {
  @override
  String get name => 'LinkUp';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderLinkUpDescription, style: const TextStyle(fontSize: 12));
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required LinkUpOptions serviceOptions,
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
          'depth': 'standard',
          'outputType': 'sourcedAnswer',
          'includeImages': 'false',
        });
        
        final response = await http.post(
          Uri.parse('https://api.linkup.so/v1/search'),
          headers: {
            'Authorization': 'Bearer ${keyConfig.key}',
            'Content-Type': 'application/json',
          },
          body: body,
        ).timeout(Duration(milliseconds: commonOptions.timeout));
        
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
        
        final data = jsonDecode(response.body);
        final sources = data['sources'] as List? ?? [];
        final results = sources.take(commonOptions.resultSize).map((item) {
          return SearchResultItem(
            title: item['name'] ?? '',
            url: item['url'] ?? '',
            text: item['snippet'] ?? '',
          );
        }).toList();
        
        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(
          answer: data['answer'],
          items: results,
        );
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('LinkUp search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}
