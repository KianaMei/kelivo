import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';
import '../../http/dio_client.dart';

class MetasoSearchService extends SearchService<MetasoOptions> {
  @override
  String get name => 'Metaso (秘塔)';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderMetasoDescription, style: const TextStyle(fontSize: 12));
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required MetasoOptions serviceOptions,
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
          'scope': 'webpage',
          'size': commonOptions.resultSize,
          'includeSummary': false,
        });
        
        final response = await simpleDio.post(
          'https://metaso.cn/api/v1/search',
          data: jsonDecode(body),
          options: Options(
            headers: {
              'Authorization': 'Bearer ${keyConfig.key}',
              'Accept': 'application/json',
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
        
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        final webpages = data['webpages'] as List? ?? [];
        final results = webpages.map((item) {
          return SearchResultItem(
            title: item['title'] ?? '',
            url: item['link'] ?? '',
            text: item['snippet'] ?? '',
          );
        }).toList();
        
        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Metaso search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}
