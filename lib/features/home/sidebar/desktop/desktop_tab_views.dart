import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../../../core/providers/settings_provider.dart';

/// Desktop: TabBarView area hosting assistants and topics lists
class DesktopTabViews extends StatelessWidget {
  const DesktopTabViews({
    super.key,
    required this.controller,
    required this.listController,
    required this.buildAssistants,
    required this.buildConversations,
    required this.newAssistantButton,
  });

  final TabController controller;
  final ScrollController listController;
  final Widget Function() buildAssistants;
  final Widget Function() buildConversations;
  final Widget newAssistantButton;

  @override
  Widget build(BuildContext context) {
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final topPad = context.watch<SettingsProvider>().showChatListDate ? (isDesktop ? 2.0 : 4.0) : 10.0;
    return TabBarView(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      children: [
        // Assistants
        Column(
          children: [
            Expanded(
              child: ListView(
                controller: listController,
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
                children: [buildAssistants()],
              ),
            ),
            newAssistantButton,
          ],
        ),
        // Topics (conversations)
        ListView(
          controller: listController,
          padding: EdgeInsets.fromLTRB(0, topPad, 0, 16),
          children: [buildConversations()],
        ),
      ],
    );
  }
}

/// Legacy (mobile/tablet): original single-list layout with optional inline assistants
class LegacyListArea extends StatelessWidget {
  const LegacyListArea({
    super.key,
    required this.listController,
    required this.isDesktop,
    required this.buildAssistants,
    required this.buildConversations,
  });

  final ScrollController listController;
  final bool isDesktop;
  final Widget Function() buildAssistants;
  final Widget Function() buildConversations;

  @override
  Widget build(BuildContext context) {
    final showDate = context.watch<SettingsProvider>().showChatListDate;
    final double topPadding = showDate ? (isDesktop ? 2.0 : 4.0) : 10.0;
    return ListView(
      controller: listController,
      padding: EdgeInsets.fromLTRB(0, topPadding, 0, 16),
      children: [
        buildAssistants(),
        const SizedBox(height: 12),
        buildConversations(),
      ],
    );
  }
}
