import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/providers/assistant_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/services/haptics.dart';
import '../../../../desktop/menu_anchor.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../../utils/avatar_cache.dart';
import '../../../../utils/local_image_provider.dart';
import '../../../../utils/platform_utils.dart';
import '../../../../utils/safe_tooltip.dart';
import '../../../../utils/sandbox_path_resolver.dart';
import '../../pages/image_viewer_page.dart';
import 'message_models.dart';
import 'message_parts.dart';
import '../../../../shared/widgets/markdown_with_highlight.dart';

/// Renders user messages with avatar, content, and action buttons.
class UserMessageRenderer extends StatefulWidget {
  final ChatMessage message;
  final bool showUserAvatar;
  final bool showUserActions;
  final bool showVersionSwitcher;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPrevVersion;
  final VoidCallback? onNextVersion;
  final VoidCallback? onCopy;
  final VoidCallback? onResend;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const UserMessageRenderer({
    super.key,
    required this.message,
    this.showUserAvatar = true,
    this.showUserActions = true,
    this.showVersionSwitcher = false,
    this.versionIndex,
    this.versionCount,
    this.onPrevVersion,
    this.onNextVersion,
    this.onCopy,
    this.onResend,
    this.onMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<UserMessageRenderer> createState() => _UserMessageRendererState();
}

class _UserMessageRendererState extends State<UserMessageRenderer> {
  final GlobalKey _userBubbleKey = GlobalKey();
  static final DateFormat _dateFormat = DateFormat('HH:mm');

  ParsedUserContent _parseUserContent(String raw) {
    final imgRe = RegExp(r"\[image:(.+?)\]");
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    final images = <String>[];
    final docs = <DocRef>[];
    final buffer = StringBuffer();
    int idx = 0;
    while (idx < raw.length) {
      final m1 = imgRe.matchAsPrefix(raw, idx);
      final m2 = fileRe.matchAsPrefix(raw, idx);
      if (m1 != null) {
        final p = m1.group(1)?.trim();
        if (p != null && p.isNotEmpty) images.add(p);
        idx = m1.end;
        continue;
      }
      if (m2 != null) {
        final path = m2.group(1)?.trim() ?? '';
        final name = m2.group(2)?.trim() ?? 'file';
        final mime = m2.group(3)?.trim() ?? 'text/plain';
        docs.add(DocRef(path: path, fileName: name, mime: mime));
        idx = m2.end;
        continue;
      }
      buffer.write(raw[idx]);
      idx++;
    }
    return ParsedUserContent(buffer.toString().trim(), images, docs);
  }

  Widget _buildUserAvatar(UserProvider userProvider, ColorScheme cs) {
    Widget avatarContent;

    if (userProvider.avatarType == 'emoji' &&
        userProvider.avatarValue != null) {
      avatarContent = Center(
        child: Text(
          userProvider.avatarValue!,
          style: const TextStyle(fontSize: 18),
        ),
      );
    } else if (userProvider.avatarType == 'url' &&
        userProvider.avatarValue != null) {
      final url = userProvider.avatarValue!;
      avatarContent = FutureBuilder<String?>(
        future: AvatarCache.getPath(url),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && !kIsWeb && PlatformUtils.fileExistsSync(p)) {
            return SizedBox(
              width: 32,
              height: 32,
              child: ClipOval(
                child: Image(
                  image: localFileImage(p),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }
          if (p != null && kIsWeb && p.startsWith('data:')) {
            return SizedBox(
              width: 32,
              height: 32,
              child: ClipOval(
                child: Image.network(
                  p,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }
          return SizedBox(
            width: 32,
            height: 32,
            child: ClipOval(
              child: Image.network(
                url,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Lucide.User, size: 18, color: cs.primary),
              ),
            ),
          );
        },
      );
    } else if (userProvider.avatarType == 'file' &&
        userProvider.avatarValue != null &&
        !kIsWeb) {
      avatarContent = FutureBuilder<String?>(
        future: AssistantProvider.resolveToAbsolutePath(
          userProvider.avatarValue!,
        ),
        builder: (ctx, snap) {
          final path = snap.data;
          if (path != null && PlatformUtils.fileExistsSync(path)) {
            return SizedBox(
              width: 32,
              height: 32,
              child: ClipOval(
                child: Image(
                  image: localFileImage(path),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Lucide.User, size: 18, color: cs.primary),
                ),
              ),
            );
          }
          return Icon(Lucide.User, size: 18, color: cs.primary);
        },
      );
    } else {
      avatarContent = Icon(Lucide.User, size: 18, color: cs.primary);
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: avatarContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userProvider = context.watch<UserProvider>();
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final parsed = _parseUserContent(widget.message.content);
    final isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 10 : 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (settings.showUserNameTimestamp)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      userProvider.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _dateFormat.format(widget.message.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              if (widget.showUserAvatar) ...[
                const SizedBox(width: 8),
                _buildUserAvatar(userProvider, cs),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            key: _userBubbleKey,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.primary.withOpacity(0.15)
                  : cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (parsed.text.isNotEmpty)
                  MarkdownWithCodeHighlight(
                    key: ValueKey('user_${widget.message.id}'),
                    text: parsed.text,
                    baseStyle: TextStyle(
                      fontSize: 15.5,
                      height: 1.4,
                      color: cs.onSurface,
                    ),
                  ),
                if (parsed.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final imgs = parsed.images;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: imgs.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final p = entry.value;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => ImageViewerPage(
                                      images: imgs,
                                      initialIndex: idx,
                                    ),
                                    transitionDuration:
                                        const Duration(milliseconds: 360),
                                    reverseTransitionDuration:
                                        const Duration(milliseconds: 280),
                                    transitionsBuilder: (
                                      context,
                                      anim,
                                      sec,
                                      child,
                                    ) {
                                      final curved = CurvedAnimation(
                                        parent: anim,
                                        curve: Curves.easeOutCubic,
                                        reverseCurve: Curves.easeInCubic,
                                      );
                                      return FadeTransition(
                                        opacity: curved,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, 0.02),
                                            end: Offset.zero,
                                          ).animate(curved),
                                          child: child,
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Hero(
                                  tag: 'img:$p',
                                  child: (() {
                                    if (p.startsWith('data:')) {
                                      try {
                                        final i = p.indexOf('base64,');
                                        if (i != -1) {
                                          return Image.memory(
                                            base64Decode(p.substring(i + 7)),
                                            width: 96,
                                            height: 96,
                                            fit: BoxFit.cover,
                                          );
                                        }
                                      } catch (_) {}
                                    }
                                    final lower = p.toLowerCase();
                                    final isUrl = lower.startsWith('http://') || lower.startsWith('https://');
                                    if (isUrl) {
                                      return Image.network(
                                        p,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 96,
                                          height: 96,
                                          color: Colors.black12,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      );
                                    }
                                    if (kIsWeb) {
                                      return Container(
                                        width: 96,
                                        height: 96,
                                        color: Colors.black12,
                                        child: const Icon(Icons.image_not_supported),
                                      );
                                    }
                                    final fixed = SandboxPathResolver.fix(p);
                                    return Image(
                                      image: localFileImage(fixed),
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 96,
                                        height: 96,
                                        color: Colors.black12,
                                        child: const Icon(Icons.broken_image),
                                      ),
                                    );
                                  })(),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
                if (parsed.docs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: parsed.docs.map((d) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          overlayColor: MaterialStateProperty.resolveWith(
                            (states) => cs.primary.withOpacity(
                              states.contains(MaterialState.pressed) ? 0.14 : 0.08,
                            ),
                          ),
                          splashColor: cs.primary.withOpacity(0.18),
                          onTap: () async {
                            try {
                              final raw = d.path.trim();
                              final lower = raw.toLowerCase();
                              final isUrl = lower.startsWith('http://') || lower.startsWith('https://');
                              if (kIsWeb) {
                                if (isUrl) {
                                  await launchUrlString(raw, mode: LaunchMode.platformDefault);
                                  return;
                                }
                                showAppSnackBar(
                                  context,
                                  message: l10n.chatMessageWidgetFileNotFound(d.fileName),
                                  type: NotificationType.error,
                                );
                                return;
                              }

                              final fixed = SandboxPathResolver.fix(raw);
                              if (!PlatformUtils.fileExistsSync(fixed)) {
                                showAppSnackBar(
                                  context,
                                  message: l10n.chatMessageWidgetFileNotFound(d.fileName),
                                  type: NotificationType.error,
                                );
                                return;
                              }

                              final res = await PlatformUtils.callPlatformMethod(
                                () => OpenFilex.open(fixed, type: d.mime),
                                fallback: OpenResult(
                                  type: ResultType.error,
                                  message: 'File opening not supported on this platform',
                                ),
                              );

                              if (res != null && res.type != ResultType.done) {
                                showAppSnackBar(
                                  context,
                                  message: l10n.chatMessageWidgetCannotOpenFile(res.message ?? res.type.toString()),
                                  type: NotificationType.error,
                                );
                              }
                            } catch (e) {
                              showAppSnackBar(
                                context,
                                message: l10n.chatMessageWidgetOpenFileError(
                                  e.toString(),
                                ),
                                type: NotificationType.error,
                              );
                            }
                          },
                          child: Ink(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : cs.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.insert_drive_file, size: 16),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      d.fileName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          if (widget.showUserActions || widget.showVersionSwitcher) ...[
            SizedBox(height: widget.showUserActions ? 4 : 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.showUserActions) ...[
                  IconButton(
                    icon: Icon(Lucide.Copy, size: 16),
                    onPressed: widget.onCopy ??
                        () {
                          Clipboard.setData(
                            ClipboardData(text: widget.message.content),
                          );
                          showAppSnackBar(
                            context,
                            message: l10n.chatMessageWidgetCopiedToClipboard,
                            type: NotificationType.success,
                          );
                        },
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                  ),
                  IconButton(
                    icon: Icon(Lucide.RefreshCw, size: 16),
                    onPressed: widget.onResend,
                    tooltip: safeTooltipMessage(l10n.chatMessageWidgetResendTooltip),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                  ),
                  Builder(
                    builder: (btnContext) {
                      return IconButton(
                        icon: Icon(Lucide.Ellipsis, size: 16),
                        onPressed: widget.onMore == null
                            ? null
                            : () {
                                final renderBox =
                                    btnContext.findRenderObject() as RenderBox?;
                                if (renderBox != null) {
                                  final offset =
                                      renderBox.localToGlobal(Offset.zero);
                                  final size = renderBox.size;
                                  DesktopMenuAnchor.setPosition(
                                    Offset(
                                      offset.dx + size.width,
                                      offset.dy + size.height / 2,
                                    ),
                                  );
                                }
                                widget.onMore!();
                              },
                        tooltip: safeTooltipMessage(l10n.chatMessageWidgetMoreTooltip),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                      );
                    },
                  ),
                ],
                if (widget.showVersionSwitcher) ...[
                  if (widget.showUserActions) const SizedBox(width: 8),
                  BranchSelector(
                    index: widget.versionIndex ?? 0,
                    total: widget.versionCount ?? 1,
                    onPrev: widget.onPrevVersion,
                    onNext: widget.onNextVersion,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
