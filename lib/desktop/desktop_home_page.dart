import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'desktop_nav_rail.dart';
import 'desktop_chat_page.dart';
import 'desktop_translate_page.dart';
import 'window_title_bar.dart';
import 'desktop_settings_page.dart';

/// Desktop home screen: left compact rail + main content.
/// Phase 1 focuses on structure and platform-appropriate interactions/hover.
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  int _tabIndex = 0; // 0=Chat, 1=Translate, 2=Settings

  @override
  Widget build(BuildContext context) {
    // Ensure a reasonable min size to avoid overflow on aggressive resize.
    const minWidth = 960.0;
    const minHeight = 640.0;

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final needsWidthPad = w < minWidth;
        final needsHeightPad = h < minHeight;

        Widget body = Row(
          children: [
            DesktopNavRail(
              activeIndex: _tabIndex,
              onTapChat: () => setState(() => _tabIndex = 0),
              onTapTranslate: () => setState(() => _tabIndex = 1),
              onTapSettings: () {
                setState(() => _tabIndex = 2);
              },
            ),
            Expanded(
              // Keep all pages alive so ongoing chat streams are not canceled
              // when switching tabs (Chat/Translate/Settings) on desktop.
              child: IndexedStack(
                index: _tabIndex,
                children: const [
                  // Chat page remains mounted
                  DesktopChatPage(),
                  // Translate page remains mounted
                  DesktopTranslatePage(key: ValueKey('translate_page')),
                  // Settings page remains mounted
                  DesktopSettingsPage(key: ValueKey('settings_page')),
                ],
              ),
            ),
          ],
        );

        // Wrap with Windows custom title bar when on Windows platform.
        final content = isWindows
            ? Column(
                children: [
                  // Align custom title bar to match kelivo-remote (icon + title on the left)
                  WindowTitleBar(
                    leftChildren: const [
                      _TitleBarLeading(),
                    ],
                  ),
                  Expanded(child: body),
                ],
              )
            : body;

        if (!needsWidthPad && !needsHeightPad) return content;

        // Center a constrained area if window is smaller than our minimum
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: minWidth, minHeight: minHeight),
            child: SizedBox(
              width: needsWidthPad ? minWidth : w,
              height: needsHeightPad ? minHeight : h,
              child: content,
            ),
          ),
        );
      },
    );
  }
}

// No extra router/shim; we import DesktopSettingsPage directly above.

class _TitleBarLeading extends StatelessWidget {
  const _TitleBarLeading({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // App icon
        Image.asset(
          'assets/icons/kelivo.png',
          width: 16,
          height: 16,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 8),
        // App name
        Text(
          'Kelivo',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withOpacity(0.8),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
