import 'package:flutter/material.dart';

Future<void> showDesktopProviderDetailDialog(
  BuildContext context, {
  required String providerKey,
  required String displayName,
}) async {}

/// Web stub: Provider detail page not available on web
class DesktopProviderDetailPage extends StatelessWidget {
  const DesktopProviderDetailPage({
    super.key,
    required this.keyName,
    required this.displayName,
    this.embedded = false,
    this.onBack,
  });

  final String keyName;
  final String displayName;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Provider configuration not available on web'),
    );
  }
}

