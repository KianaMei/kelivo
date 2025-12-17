import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:characters/characters.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import '../../../core/services/http/dio_client.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/upload/upload_service.dart';

/// Input row widget for forms.
class InputRow extends StatelessWidget {
  const InputRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.onChanged,
    this.enabled = true,
    this.suffix,
    this.keyboardType,
    this.hideLabel = false,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hideLabel) ...[
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  enabled: enabled,
                  controller: controller,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: suffix!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Brand avatar widget displaying model/provider icon.
class BrandAvatarLike extends StatelessWidget {
  const BrandAvatarLike({super.key, required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? asset;
    asset = BrandAssets.assetForName(name);
    if (asset != null) {
      if (asset!.endsWith('.svg')) {
        final isColorful = asset!.contains('color');
        final ColorFilter? tint =
            (isDark && !isColorful)
                ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset!,
            width: size * 0.62,
            height: size * 0.62,
            colorFilter: tint,
          ),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Image.asset(
            asset!,
            width: size * 0.62,
            height: size * 0.62,
            fit: BoxFit.contain,
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Desktop context menu for assistant avatar selection.
void showAvatarContextMenu(BuildContext context, Assistant a, Offset position) {
  final overlay = Overlay.of(context);
  if (overlay == null) return;

  late OverlayEntry entry;

  void closeMenu() {
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => AssistantAvatarContextMenu(
      position: position,
      onClose: closeMenu,
      onChooseImage: () async {
        closeMenu();
        await pickLocalImageForAssistant(context, a);
      },
      onChooseEmoji: () async {
        closeMenu();
        final emoji = await pickEmojiForAssistant(context);
        if (emoji != null && context.mounted) {
          await context.read<AssistantProvider>().updateAssistant(
            a.copyWith(avatar: emoji),
          );
        }
      },
      onEnterLink: () async {
        closeMenu();
        await inputAvatarUrlForAssistant(context, a);
      },
      onImportQQ: () async {
        closeMenu();
        await inputQQAvatarForAssistant(context, a);
      },
      onReset: () async {
        closeMenu();
        if (context.mounted) {
          await context.read<AssistantProvider>().updateAssistant(
            a.copyWith(clearAvatar: true),
          );
        }
      },
    ),
  );

  overlay.insert(entry);
}

/// Emoji picker dialog for assistant avatar.
Future<String?> pickEmojiForAssistant(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String value = '';
  bool validGrapheme(String s) {
    final trimmed = s.characters.take(1).toString().trim();
    return trimmed.isNotEmpty && trimmed == s.trim();
  }

  final List<String> quick = const [
    '😀', '😁', '😂', '🤣', '😃', '😄', '😅', '😊', '😍', '😘', '😗', '😙', '😚', '🙂', '🤗', '🤩',
    '🫶', '🤝', '👍', '👎', '👋', '🙏', '💪', '🔥', '✨', '🌟', '💡', '🎉', '🎊', '🎈', '🌈', '☀️',
    '🌙', '⭐', '⚡', '☁️', '❄️', '🌧️', '🍎', '🍊', '🍋', '🍉', '🍇', '🍓', '🍒', '🍑', '🥭', '🍍',
    '🥝', '🍅', '🥕', '🌽', '🍞', '🧀', '🍔', '🍟', '🍕', '🌮', '🌯', '🍣', '🍜', '🍰', '🍪', '🍩',
    '🍫', '🍻', '☕', '🧋', '🥤', '⚽', '🏀', '🏈', '🎾', '🏐', '🎮', '🎧', '🎸', '🎹', '🎺', '📚',
    '✏️', '💼', '💻', '🖥️', '📱', '🛩️', '✈️', '🚗', '🚕', '🚙', '🚌', '🚀', '🛰️', '🧠', '🫀', '💊',
    '🩺', '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵',
  ];
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final media = MediaQuery.of(ctx);
          final avail = media.size.height - media.viewInsets.bottom;
          final double gridHeight = (avail * 0.28).clamp(120.0, 220.0);
          return AlertDialog(
            scrollable: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: cs.surface,
            title: Text(l10n.assistantEditEmojiDialogTitle),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: cs.primary.withOpacity(0.08), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(value.isEmpty ? '🙂' : value.characters.take(1).toString(), style: const TextStyle(fontSize: 40)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (v) => setLocal(() => value = v),
                    onSubmitted: (_) {
                      if (validGrapheme(value)) Navigator.of(ctx).pop(value.characters.take(1).toString());
                    },
                    decoration: InputDecoration(
                      hintText: l10n.assistantEditEmojiDialogHint,
                      filled: true,
                      fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: gridHeight,
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                      itemCount: quick.length,
                      itemBuilder: (c, i) {
                        final e = quick[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(ctx).pop(e),
                          child: Container(
                            decoration: BoxDecoration(color: cs.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                            alignment: Alignment.center,
                            child: Text(e, style: const TextStyle(fontSize: 20)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.assistantEditEmojiDialogCancel)),
              TextButton(
                onPressed: validGrapheme(value) ? () => Navigator.of(ctx).pop(value.characters.take(1).toString()) : null,
                child: Text(l10n.assistantEditEmojiDialogSave, style: TextStyle(color: validGrapheme(value) ? cs.primary : cs.onSurface.withOpacity(0.38), fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      );
    },
  );
}

/// URL input dialog for assistant avatar.
Future<void> inputAvatarUrlForAssistant(BuildContext context, Assistant a) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      bool valid(String s) => s.trim().startsWith('http://') || s.trim().startsWith('https://');
      String value = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: cs.surface,
            title: Text(l10n.assistantEditImageUrlDialogTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.assistantEditImageUrlDialogHint,
                filled: true,
                fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
              ),
              onChanged: (v) => setLocal(() => value = v),
              onSubmitted: (_) {
                if (valid(value)) Navigator.of(ctx).pop(true);
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.assistantEditImageUrlDialogCancel)),
              TextButton(
                onPressed: valid(value) ? () => Navigator.of(ctx).pop(true) : null,
                child: Text(l10n.assistantEditImageUrlDialogSave, style: TextStyle(color: valid(value) ? cs.primary : cs.onSurface.withOpacity(0.38), fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      );
    },
  );
  if (ok == true) {
    final url = controller.text.trim();
    if (url.isNotEmpty) {
      await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: url));
    }
  }
}

/// QQ avatar input dialog for assistant avatar.
Future<void> inputQQAvatarForAssistant(BuildContext context, Assistant a) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      String value = '';
      bool valid(String s) => RegExp(r'^[0-9]{5,12}$').hasMatch(s.trim());
      String randomQQ() {
        final lengths = <int>[5, 6, 7, 8, 9, 10, 11];
        final weights = <int>[1, 20, 80, 100, 500, 5000, 80];
        final total = weights.fold<int>(0, (a, b) => a + b);
        final rnd = math.Random();
        int roll = rnd.nextInt(total) + 1;
        int chosenLen = lengths.last;
        int acc = 0;
        for (int i = 0; i < lengths.length; i++) {
          acc += weights[i];
          if (roll <= acc) {
            chosenLen = lengths[i];
            break;
          }
        }
        final sb = StringBuffer();
        final firstGroups = <List<int>>[
          [1, 2],
          [3, 4],
          [5, 6, 7, 8],
          [9],
        ];
        final firstWeights = <int>[128, 4, 2, 1];
        final firstTotal = firstWeights.fold<int>(0, (a, b) => a + b);
        int r2 = rnd.nextInt(firstTotal) + 1;
        int idx = 0;
        int a2 = 0;
        for (int i = 0; i < firstGroups.length; i++) {
          a2 += firstWeights[i];
          if (r2 <= a2) {
            idx = i;
            break;
          }
        }
        final group = firstGroups[idx];
        sb.write(group[rnd.nextInt(group.length)]);
        for (int i = 1; i < chosenLen; i++) {
          sb.write(rnd.nextInt(10));
        }
        return sb.toString();
      }

      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: cs.surface,
            title: Text(l10n.assistantEditQQAvatarDialogTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: l10n.assistantEditQQAvatarDialogHint,
                filled: true,
                fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
              ),
              onChanged: (v) => setLocal(() => value = v),
              onSubmitted: (_) {
                if (valid(value)) Navigator.of(ctx).pop(true);
              },
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () async {
                  const int maxTries = 20;
                  bool applied = false;
                  for (int i = 0; i < maxTries; i++) {
                    final qq = randomQQ();
                    final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=100';
                    try {
                      final resp = await simpleDio.get<List<int>>(
                        url,
                        options: Options(
                          responseType: ResponseType.bytes,
                          receiveTimeout: const Duration(seconds: 5),
                        ),
                      );
                      final bytes = resp.data ?? [];
                      if (resp.statusCode == 200 && bytes.isNotEmpty) {
                        await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: url));
                        applied = true;
                        break;
                      }
                    } catch (_) {}
                  }
                  if (applied) {
                    if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(false);
                  } else {
                    showAppSnackBar(context, message: l10n.assistantEditQQAvatarFailedMessage, type: NotificationType.error);
                  }
                },
                child: Text(l10n.assistantEditQQAvatarRandomButton),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.assistantEditQQAvatarDialogCancel)),
                  TextButton(
                    onPressed: valid(value) ? () => Navigator.of(ctx).pop(true) : null,
                    child: Text(l10n.assistantEditQQAvatarDialogSave, style: TextStyle(color: valid(value) ? cs.primary : cs.onSurface.withOpacity(0.38), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
  if (ok == true) {
    final qq = controller.text.trim();
    if (qq.isNotEmpty) {
      final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=100';
      await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: url));
    }
  }
}

/// Pick local image for assistant avatar.
Future<void> pickLocalImageForAssistant(BuildContext context, Assistant a) async {
  try {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    final path = f.path;

    if (kIsWeb) {
      if (bytes == null) {
        showAppSnackBar(context, message: 'Unable to read image', type: NotificationType.error);
        return;
      }
      final sp = context.read<SettingsProvider>();
      final providerKey = sp.currentModelProvider;
      final accessCode = providerKey != null ? sp.getProviderConfig(providerKey).apiKey : null;
      final url = await UploadService.uploadBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: 'assistant_avatar_${a.id}_${DateTime.now().millisecondsSinceEpoch}.${extFromName(f.name)}',
        contentType: mimeFromName(f.name),
        accessCode: accessCode,
      );
      await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: url));
      return;
    }

    if (path == null || path.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(context, message: l10n.assistantEditGeneralErrorMessage, type: NotificationType.error);
      await inputAvatarUrlForAssistant(context, a);
      return;
    }
    await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: path));
    return;
  } on PlatformException catch (e) {
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(context, message: l10n.assistantEditGalleryErrorMessage, type: NotificationType.error);
    await inputAvatarUrlForAssistant(context, a);
    return;
  } catch (_) {
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(context, message: l10n.assistantEditGeneralErrorMessage, type: NotificationType.error);
    await inputAvatarUrlForAssistant(context, a);
    return;
  }
}

/// Extract file extension from name.
String extFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.webp')) return 'webp';
  if (lower.endsWith('.gif')) return 'gif';
  return 'jpg';
}

/// Get MIME type from file name.
String mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/*';
}

/// Glass morphism context menu for assistant avatar.
class AssistantAvatarContextMenu extends StatefulWidget {
  const AssistantAvatarContextMenu({
    super.key,
    required this.position,
    required this.onClose,
    required this.onChooseImage,
    required this.onChooseEmoji,
    required this.onEnterLink,
    required this.onImportQQ,
    required this.onReset,
  });

  final Offset position;
  final VoidCallback onClose;
  final VoidCallback onChooseImage;
  final VoidCallback onChooseEmoji;
  final VoidCallback onEnterLink;
  final VoidCallback onImportQQ;
  final VoidCallback onReset;

  @override
  State<AssistantAvatarContextMenu> createState() => _AssistantAvatarContextMenuState();
}

class _AssistantAvatarContextMenuState extends State<AssistantAvatarContextMenu> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final screen = MediaQuery.of(context).size;

    const menuWidth = 160.0;
    const menuHeight = 240.0;

    double left = widget.position.dx;
    double top = widget.position.dy;

    if (left + menuWidth > screen.width - 8) {
      left = screen.width - menuWidth - 8;
    }
    if (top + menuHeight > screen.height - 8) {
      top = screen.height - menuHeight - 8;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              alignment: Alignment.topLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: menuWidth,
                    decoration: BoxDecoration(
                      color: isDark ? cs.surface.withOpacity(0.75) : cs.surface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white.withOpacity(0.1) : cs.outlineVariant.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AvatarMenuItem(icon: Lucide.Image, label: l10n.assistantEditAvatarChooseImage, onTap: widget.onChooseImage),
                          AvatarMenuItem(icon: Lucide.Smile, label: l10n.assistantEditAvatarChooseEmoji, onTap: widget.onChooseEmoji),
                          AvatarMenuItem(icon: Lucide.Link, label: l10n.assistantEditAvatarEnterLink, onTap: widget.onEnterLink),
                          AvatarMenuItem(icon: Lucide.User, label: l10n.assistantEditAvatarImportQQ, onTap: widget.onImportQQ),
                          AvatarMenuItem(icon: Lucide.RotateCcw, label: l10n.assistantEditAvatarReset, onTap: widget.onReset),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Avatar context menu item.
class AvatarMenuItem extends StatefulWidget {
  const AvatarMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<AvatarMenuItem> createState() => _AvatarMenuItemState();
}

class _AvatarMenuItemState extends State<AvatarMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05))
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: cs.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
