import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../services/search_service_factory.dart';
import '../services/search_service_names.dart';

/// Builds form fields for a given service type
class ServiceFormFields extends StatelessWidget {
  const ServiceFormFields({
    super.key,
    required this.type,
    required this.controllers,
  });

  final String type;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget textField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      controllers[key] ??= TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextFormField(
          controller: controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }

    Widget infoBox(String text) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Lucide.Search, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.8)),
            ),
          ),
        ],
      ),
    );

    switch (type) {
      case 'bing_local':
        return infoBox(l10n.searchServiceNameBingLocal);
      case 'duckduckgo':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            infoBox(l10n.searchServiceNameDuckDuckGo),
            const SizedBox(height: 12),
            textField(key: 'region', label: 'Region (optional)', hint: 'wt-wt'),
          ],
        );
      case 'searxng':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            textField(
              key: 'url',
              label: l10n.searchServicesAddDialogInstanceUrl,
              validator: (v) => (v == null || v.isEmpty) ? l10n.searchServicesAddDialogUrlRequired : null,
            ),
            const SizedBox(height: 12),
            textField(key: 'engines', label: l10n.searchServicesAddDialogEnginesOptional, hint: 'google,duckduckgo'),
            const SizedBox(height: 12),
            textField(key: 'language', label: l10n.searchServicesAddDialogLanguageOptional, hint: 'en-US'),
            const SizedBox(height: 12),
            textField(key: 'username', label: l10n.searchServicesAddDialogUsernameOptional),
            const SizedBox(height: 12),
            textField(key: 'password', label: l10n.searchServicesAddDialogPasswordOptional, obscureText: true),
          ],
        );
      default:
        // API key only types
        if (SearchServiceFactory.needsApiKeyOnly(type)) {
          return textField(
            key: 'apiKey',
            label: 'API Key',
            validator: (v) => (v == null || v.isEmpty) ? l10n.searchServicesAddDialogApiKeyRequired : null,
          );
        }
        return const SizedBox.shrink();
    }
  }
}
