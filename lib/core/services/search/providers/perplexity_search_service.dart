import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';
import '../../http/dio_client.dart';

class PerplexitySearchService extends SearchService<PerplexityOptions> {
  @override
  String get name => 'Perplexity';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderPerplexityDescription, style: const TextStyle(fontSize: 12));
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required PerplexityOptions serviceOptions,
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
        final body = <String, dynamic>{
          'query': query,
          'max_results': commonOptions.resultSize.clamp(1, 20),
        };

        if (serviceOptions.country != null && serviceOptions.country!.trim().isNotEmpty) {
          body['country'] = serviceOptions.country!.trim();
        }
        if (serviceOptions.searchDomainFilter != null && serviceOptions.searchDomainFilter!.isNotEmpty) {
          body['search_domain_filter'] = serviceOptions.searchDomainFilter;
        }
        if (serviceOptions.maxTokensPerPage != null) {
          body['max_tokens_per_page'] = serviceOptions.maxTokensPerPage;
        }

        final response = await simpleDio.post(
          'https://api.perplexity.ai/search',
          data: body,
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
        final resultsList = (data['results'] as List?) ?? const <dynamic>[];
        // Support both single-query (list of items) and multi-query (list of lists)
        final flat = <Map<String, dynamic>>[];
        for (final item in resultsList) {
          if (item is List) {
            for (final sub in item) {
              if (sub is Map<String, dynamic>) flat.add(sub);
            }
          } else if (item is Map<String, dynamic>) {
            flat.add(item);
          }
        }

        final items = flat.take(commonOptions.resultSize).map((m) {
          return SearchResultItem(
            title: (m['title'] ?? '').toString(),
            url: (m['url'] ?? '').toString(),
            text: (m['snippet'] ?? '').toString(),
          );
        }).toList();

        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: items);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Perplexity search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}

