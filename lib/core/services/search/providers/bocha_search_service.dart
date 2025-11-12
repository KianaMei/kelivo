import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class BochaSearchService extends SearchService<BochaOptions> {
  @override
  String get name => 'Bocha';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderBochaDescription, style: const TextStyle(fontSize: 12));
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required BochaOptions serviceOptions,
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
          if (serviceOptions.freshness != null && serviceOptions.freshness!.isNotEmpty)
            'freshness': serviceOptions.freshness,
          'summary': serviceOptions.summary,
          'count': commonOptions.resultSize,
          if (serviceOptions.include != null && serviceOptions.include!.isNotEmpty)
            'include': serviceOptions.include,
          if (serviceOptions.exclude != null && serviceOptions.exclude!.isNotEmpty)
            'exclude': serviceOptions.exclude,
        };

        final response = await http
            .post(
              Uri.parse('https://api.bochaai.com/v1/web-search'),
              headers: {
                'Authorization': 'Bearer ${keyConfig.key}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(Duration(milliseconds: commonOptions.timeout));

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
        if ((data['code'] as int?) != 200) {
          serviceOptions.markKeyFailure(keyConfig.id, error: 'api_error_${data['code']}');
          lastError = Exception('API error code: ${data['code']}');
          continue;
        }
        final d = (data['data'] ?? const {}) as Map<String, dynamic>;
        final webPages = (d['webPages'] ?? const {}) as Map<String, dynamic>;
        final value = (webPages['value'] as List?) ?? const <dynamic>[];

        final results = value.take(commonOptions.resultSize).map((item) {
          final m = (item as Map).cast<String, dynamic>();
          return SearchResultItem(
            title: (m['name'] ?? '').toString(),
            url: (m['url'] ?? '').toString(),
            text: ((m['summary'] ?? m['snippet']) ?? '').toString(),
          );
        }).toList();

        serviceOptions.markKeyAsUsed(keyConfig.id);
        return SearchResult(items: results);
      } catch (e) {
        serviceOptions.markKeyFailure(keyConfig.id, error: e.toString());
        lastError = e is Exception ? e : Exception('Bocha search failed: $e');
        continue;
      }
    }
    
    throw lastError ?? Exception('All API keys failed or unavailable');
  }
}

