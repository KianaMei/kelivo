import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';

/// Desktop: Header tabs (Assistants / Topics)
class DesktopSidebarTabs extends StatefulWidget {
  const DesktopSidebarTabs({super.key, required this.textColor, required this.controller});
  final Color textColor;
  final TabController controller;

  @override
  State<DesktopSidebarTabs> createState() => _DesktopSidebarTabsState();
}

class _DesktopSidebarTabsState extends State<DesktopSidebarTabs> {
  bool _hoverLeft = false;
  bool _hoverRight = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuildOnTabChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuildOnTabChanged);
    super.dispose();
  }

  void _rebuildOnTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final idx = widget.controller.index;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double pad = 4;
            final double segW = (constraints.maxWidth - pad * 2) / 2;
            return Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade200.withOpacity(0.80),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Selection knob
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    left: pad + (idx == 0 ? 0 : segW),
                    top: pad,
                    bottom: pad,
                    width: segW,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(isDark ? 0.16 : 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  // Left segment
                  Row(
                    children: [
                      Expanded(
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoverLeft = true),
                          onExit: (_) => setState(() => _hoverLeft = false),
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.controller.animateTo(0, duration: const Duration(milliseconds: 140), curve: Curves.easeOutCubic),
                            child: Stack(
                              children: [
                                // Hover wash
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOutCubic,
                                  opacity: _hoverLeft && idx != 0 ? 1 : 0,
                                  child: Container(
                                    margin: EdgeInsets.all(pad),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                ),
                                // Label
                                Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 140),
                                    curve: Curves.easeOutCubic,
                                    style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: idx == 0 ? cs.primary : widget.textColor.withOpacity(0.78),
                                    ),
                                    child: Text(l10n.desktopSidebarTabAssistants, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoverRight = true),
                          onExit: (_) => setState(() => _hoverRight = false),
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.controller.animateTo(1, duration: const Duration(milliseconds: 140), curve: Curves.easeOutCubic),
                            child: Stack(
                              children: [
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOutCubic,
                                  opacity: _hoverRight && idx != 1 ? 1 : 0,
                                  child: Container(
                                    margin: EdgeInsets.all(pad),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 140),
                                    curve: Curves.easeOutCubic,
                                    style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: idx == 1 ? cs.primary : widget.textColor.withOpacity(0.78),
                                    ),
                                    child: Text(l10n.desktopSidebarTabTopics, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
