import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';
import '../../http/dio_client.dart';

class BraveSearchService extends SearchService<BraveOptions> {
  @override
  String get name => 'Brave Search';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderBraveDescription, style: const TextStyle(fontSize: 12));
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required BraveOptions serviceOptions,
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
        final encodedQuery = Uri.encodeComponent(query);
        final url = 'https://api.search.brave.com/res/v1/web/search?q=$encodedQuery&count=${commonOptions.resultSize}';
        
        final response = await simpleDio.get(
          url,
          options: Options(
            headers: {
              'Accept': 'application/json',
              'X-Subscription-Token': keyConfig.key,
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
        
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        final webResults = data['web']?['results'] as List? ?? [];
        final results = webResults.map((item) {
          return SearchResultItem(
            title: item['title'] ?? '',
            url: item['url'] ?? '',
            text: item['description'] ?? '',
          );
        }).toList();
        
        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Brave search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}
