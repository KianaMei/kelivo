import '../../../l10n/app_localizations.dart';

/// Get localized service name by type
String getSearchServiceName(String type, AppLocalizations l10n) {
  switch (type) {
    case 'bing_local': return l10n.searchServiceNameBingLocal;
    case 'tavily': return l10n.searchServiceNameTavily;
    case 'exa': return l10n.searchServiceNameExa;
    case 'zhipu': return l10n.searchServiceNameZhipu;
    case 'searxng': return l10n.searchServiceNameSearXNG;
    case 'linkup': return l10n.searchServiceNameLinkUp;
    case 'brave': return l10n.searchServiceNameBrave;
    case 'metaso': return l10n.searchServiceNameMetaso;
    case 'jina': return l10n.searchServiceNameJina;
    case 'ollama': return l10n.searchServiceNameOllama;
    case 'perplexity': return l10n.searchServiceNamePerplexity;
    case 'bocha': return l10n.searchServiceNameBocha;
    case 'duckduckgo': return l10n.searchServiceNameDuckDuckGo;
    default: return type;
  }
}
