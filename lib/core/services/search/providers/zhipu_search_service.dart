import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class ZhipuSearchService extends SearchService<ZhipuOptions> {
  @override
  String get name => 'Zhipu (智谱)';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderZhipuDescription, style: const TextStyle(fontSize: 12));
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required ZhipuOptions serviceOptions,
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
          'search_query': query,
          'search_engine': 'search_std',
          'count': commonOptions.resultSize,
        });
        
        final response = await http.post(
          Uri.parse('https://open.bigmodel.cn/api/paas/v4/web_search'),
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
        final searchResult = data['search_result'] ?? [];
        final results = (searchResult as List).map((item) {
          return SearchResultItem(
            title: item['title'] ?? '',
            url: item['link'] ?? '',
            text: item['content'] ?? '',
          );
        }).toList();
        
        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Zhipu search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}
