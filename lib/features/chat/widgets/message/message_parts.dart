import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared UI components for message rendering.
///
/// This file contains small, reusable widgets that are used across
/// different message types (user and assistant messages).

/// Branch/version selector for message versions.
class BranchSelector extends StatelessWidget {
  const BranchSelector({
    super.key,
    required this.index,
    required this.total,
    this.onPrev,
    this.onNext,
  });
  
  final int index; // zero-based
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canPrev = index > 0;
    final canNext = index < total - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: canPrev ? onPrev : null,
          borderRadius: BorderRadius.circular(6),
          child: Icon(
            Lucide.ChevronLeft,
            size: 16,
            color: canPrev ? cs.onSurface : cs.onSurface.withOpacity(0.35),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${index + 1}/$total',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: canNext ? onNext : null,
          borderRadius: BorderRadius.circular(6),
          child: Icon(
            Lucide.ChevronRight,
            size: 16,
            color: canNext ? cs.onSurface : cs.onSurface.withOpacity(0.35),
          ),
        ),
      ],
    );
  }
}

/// Loading indicator with breathing animation (similar to OpenAI's style).
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key});

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    // Smoother, symmetric breathing with reverse to avoid jump cuts
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);

    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        // Scale and opacity gently breathe in sync
        final scale = 0.9 + 0.2 * _curve.value; // 0.9 -> 1.1
        final opacity = 0.6 + 0.4 * _curve.value; // 0.6 -> 1.0
        final base = cs.primary;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: base.withOpacity(opacity),
              boxShadow: [
                BoxShadow(
                  color: base.withOpacity(0.35 * opacity),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Citations/sources list display.
class SourcesList extends StatelessWidget {
  const SourcesList({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l10n.chatMessageWidgetCitationsTitle(items.length),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ),
          for (int i = 0; i < items.length; i++)
            SourceRow(
              index: (items[i]['index'] ?? (i + 1)).toString(),
              title: (items[i]['title'] ?? '').toString(),
              url: (items[i]['url'] ?? '').toString(),
            ),
        ],
      ),
    );
  }
}

/// Single source/citation row.
class SourceRow extends StatelessWidget {
  const SourceRow({
    super.key,
    required this.index,
    required this.title,
    required this.url,
  });
  
  final String index;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.20),
              borderRadius: BorderRadius.circular(9),
            ),
            margin: const EdgeInsets.only(top: 2),
            child: Text(index, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () async {
                try {
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {}
              },
              child: Text(
                title.isNotEmpty ? title : url,
                style: TextStyle(color: cs.primary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary card showing citation count (clickable to expand).
class SourcesSummaryCard extends StatelessWidget {
  const SourcesSummaryCard({
    super.key,
    required this.count,
    required this.onTap,
  });
  
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final label = l10n.chatMessageWidgetCitationsCount(count);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            // Match deep thinking (reasoning) card background
            color: cs.primaryContainer.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.30,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Lucide.BookOpen, size: 16, color: cs.secondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight shimmer effect for loading states.
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final bool enabled;
  
  const ShimmerEffect({
    super.key,
    required this.child,
    this.enabled = false,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with TickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.enabled) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant ShimmerEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_c.isAnimating) _c.repeat();
    if (!widget.enabled && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value; // 0..1
        return ShaderMask(
          shaderCallback: (rect) {
            final width = rect.width;
            final gradientWidth = width * 0.4;
            final dx = (width + gradientWidth) * t - gradientWidth;
            final shaderRect = Rect.fromLTWH(
              -dx,
              0,
              width + gradientWidth * 2,
              rect.height,
            );
            return LinearGradient(
              colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.35),
                Colors.white.withOpacity(0.0),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(shaderRect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Simple marquee that scrolls horizontally if text exceeds maxWidth.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double maxWidth;
  final Duration duration;
  
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.maxWidth = 160,
    this.duration = const Duration(milliseconds: 3000),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _measure(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
      textScaleFactor: MediaQuery.of(context).textScaleFactor,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.maxWidth;
    final textWidth = _measure(widget.text, widget.style);
    final needScroll = textWidth > w;
    final gap = 32.0;
    final loopWidth = textWidth + gap;
    return SizedBox(
      width: w,
      height: (widget.style.fontSize ?? 13) * 1.35,
      child: ClipRect(
        child: needScroll
            ? AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = Curves.linear.transform(_c.value);
                  final dx = -loopWidth * t;
                  return ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.0, 0.07, 0.93, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.text,
                            style: widget.style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          SizedBox(width: gap),
                          Text(
                            widget.text,
                            style: widget.style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
      ),
    );
  }
}

/// Token usage display with hover tooltip and expandable rounds.
class TokenUsageDisplay extends StatefulWidget {
  final String tokenText;
  final List<String> tooltipLines;
  final bool hasCache;
  final ColorScheme colorScheme;
  final List<Map<String, int>>? rounds;

  const TokenUsageDisplay({
    super.key,
    required this.tokenText,
    required this.tooltipLines,
    required this.hasCache,
    required this.colorScheme,
    this.rounds,
  });

  @override
  State<TokenUsageDisplay> createState() => _TokenUsageDisplayState();
}

class _TokenUsageDisplayState extends State<TokenUsageDisplay> {
  bool _isHovering = false;
  bool _isExpanded = false;
  bool _isHoveringCard = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _removeOverlay() {
    if (!mounted) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() {
      _isExpanded = false;
      _isHoveringCard = false;
    });
  }

  void _showOverlay(BuildContext context) {
    final shouldShowBackground = _isExpanded;
    
    _overlayEntry?.remove();
    _overlayEntry = null;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          if (shouldShowBackground)
            GestureDetector(
              onTap: _handleOutsideTap,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          Positioned(
            left: offset.dx,
            top: offset.dy + size.height + 4,
            child: MouseRegion(
              onEnter: (_) {
                setState(() => _isHoveringCard = true);
              },
              onExit: (_) {
                setState(() => _isHoveringCard = false);
                if (!_isHovering && !_isExpanded) {
                  _removeOverlay();
                }
              },
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: Colors.transparent,
                  elevation: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: widget.colorScheme.surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.colorScheme.outlineVariant
                                .withOpacity(0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: SelectionArea(
                          key: ValueKey('token_usage_${widget.tokenText.length}_${widget.tooltipLines.length}'),
                          child: IntrinsicWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: widget.tooltipLines.map((line) {
                                final isDivider = line == '---';
                                final isHeader =
                                    line.endsWith(':') && !line.startsWith(' ');
                                final isSubItem = line.startsWith('  ');

                                if (isDivider) {
                                  return Container(
                                    height: 1,
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    color: widget.colorScheme.outlineVariant
                                        .withOpacity(0.5),
                                  );
                                }

                                return Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isHeader ? 3 : 1.5,
                                  ),
                                  child: Text(
                                    line,
                                    style: TextStyle(
                                      fontSize: isHeader ? 12 : 11,
                                      fontWeight: isHeader
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isHeader
                                          ? widget.colorScheme.primary
                                              .withOpacity(0.9)
                                          : widget.colorScheme.onSurface
                                              .withOpacity(isSubItem ? 0.7 : 0.9),
                                      fontFamily: 'monospace',
                                      height: 1.2,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.tokenText,
          style: TextStyle(
            fontSize: 11,
            color: widget.hasCache
                ? widget.colorScheme.primary.withOpacity(0.7)
                : widget.colorScheme.onSurface.withOpacity(0.5),
            fontFamily: 'monospace',
          ),
        ),
        if (widget.rounds != null && widget.rounds!.length > 1) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.info_outline,
            size: 12,
            color: widget.colorScheme.primary.withOpacity(0.6),
          ),
        ],
      ],
    );

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovering = true;
          _isExpanded = false;
        });
        _showOverlay(context);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!_isHoveringCard && !_isExpanded && _overlayEntry != null) {
            _removeOverlay();
          }
        });
      },
      cursor: SystemMouseCursors.help,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_overlayEntry == null) {
            setState(() => _isExpanded = true);
            _showOverlay(context);
          } else {
            setState(() => _isExpanded = false);
            _removeOverlay();
          }
        },
        onLongPress: () {
          if (_overlayEntry == null) {
            setState(() => _isExpanded = true);
            _showOverlay(context);
          }
        },
        child: content,
      ),
    );
  }

  void _handleOutsideTap() {
    if (_overlayEntry != null) {
      _removeOverlay();
    }
  }
}

/// LobeChat-style horizontal scrolling search result cards.
class SearchResultCards extends StatefulWidget {
  const SearchResultCards({
    super.key,
    required this.items,
    this.onTap,
  });

  final List<Map<String, dynamic>> items;
  final Function(String url)? onTap;

  @override
  State<SearchResultCards> createState() => _SearchResultCardsState();
}

class _SearchResultCardsState extends State<SearchResultCards> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy;
      _scrollController.jumpTo(
        (_scrollController.offset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 64,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.02, 0.96, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return SearchResultCard(
                  title: (item['title'] ?? '').toString(),
                  url: (item['url'] ?? '').toString(),
                  onTap: widget.onTap,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Single search result card with favicon and domain.
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.title,
    required this.url,
    this.onTap,
  });

  final String title;
  final String url;
  final Function(String url)? onTap;

  /// Extract domain from a string that might be a URL or just a domain name
  static String? _extractDomain(String input) {
    if (input.isEmpty) return null;

    // If it looks like a domain (e.g., "reddit.com", "www.youtube.com")
    final domainPattern = RegExp(r'^(?:https?://)?(?:www\.)?([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)');
    final match = domainPattern.firstMatch(input);
    if (match != null) {
      return match.group(1);
    }

    // Try parsing as URL
    try {
      final uri = Uri.parse(input.startsWith('http') ? input : 'https://$input');
      if (uri.host.isNotEmpty) {
        return uri.host.replaceFirst('www.', '');
      }
    } catch (_) {}

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Try to extract domain from title first (for proxy URLs like Vertex AI Search)
    // Title often contains the actual website domain like "reddit.com" or "youtube.com"
    String? faviconHost = _extractDomain(title);
    String displayDomain = faviconHost ?? '';
    String displayTitle = title;

    // If title doesn't look like a domain, try URL
    if (faviconHost == null || faviconHost.isEmpty) {
      try {
        final uri = Uri.parse(url);
        faviconHost = uri.host;
        displayDomain = uri.host.replaceFirst('www.', '');
        if (title.isEmpty || title == url) {
          displayTitle = uri.host + (uri.path.length > 1 ? uri.path : '');
        }
      } catch (_) {
        displayDomain = url;
        faviconHost = url;
      }
    } else {
      // Title is a domain, use it but keep original title for display if different
      if (title.toLowerCase() == faviconHost.toLowerCase() ||
          title.toLowerCase() == 'www.$faviconHost'.toLowerCase()) {
        // Title is just the domain, show URL path instead
        try {
          final uri = Uri.parse(url);
          if (uri.path.length > 1) {
            displayTitle = faviconHost + uri.path;
          }
        } catch (_) {}
      }
    }

    // Ensure faviconHost is valid for URL
    final validFaviconHost = (faviconHost != null && faviconHost.isNotEmpty && faviconHost.contains('.'))
        ? faviconHost
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap?.call(url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title - max 2 lines with ellipsis
              Expanded(
                child: Text(
                  displayTitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 3),
              // Favicon + domain
              Row(
                children: [
                  // Use DuckDuckGo for favicon
                  if (validFaviconHost != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Image.network(
                        'https://icons.duckduckgo.com/ip3/$validFaviconHost.ico',
                        width: 10,
                        height: 10,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.language,
                          size: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.language,
                      size: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      displayDomain,
                      style: TextStyle(
                        fontSize: 8,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
