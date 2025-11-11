import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/snackbar.dart';
import '../../utils/provider_avatar_manager.dart';
import '../../utils/brand_assets.dart';
import '../../icons/lucide_adapter.dart';

/// Desktop-style avatar picker dialog for provider custom avatar
/// Replaces the mobile BottomSheet with a desktop-native Dialog
Future<void> showDesktopAvatarPickerDialog(
  BuildContext context, {
  required String providerKey,
  required String displayName,
}) async {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'avatar-picker',
    barrierColor: Colors.black.withOpacity(0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _DesktopAvatarPickerDialog(
      providerKey: providerKey,
      displayName: displayName,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DesktopAvatarPickerDialog extends StatefulWidget {
  const _DesktopAvatarPickerDialog({
    required this.providerKey,
    required this.displayName,
  });

  final String providerKey;
  final String displayName;

  @override
  State<_DesktopAvatarPickerDialog> createState() => _DesktopAvatarPickerDialogState();
}

class _DesktopAvatarPickerDialogState extends State<_DesktopAvatarPickerDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);
    final hasCustom = cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Custom Avatar',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _IconBtn(
                    icon: Lucide.X,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Preview
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.04)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.12),
                  ),
                ),
                child: Column(
                  children: [
                    _BrandAvatar(
                      key: ValueKey(cfg.customAvatarPath),
                      name: cfg.name.isNotEmpty ? cfg.name : widget.displayName,
                      providerKey: widget.providerKey,
                      size: 64,
                      customAvatarPath: cfg.customAvatarPath,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasCustom ? 'Custom' : 'Default',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                _ActionButton(
                  icon: Lucide.Image,
                  label: 'Choose local image',
                  onTap: () => _pickLocalImage(context),
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.emoji_emotions,
                  label: 'Choose emoji',
                  onTap: () => _pickEmoji(context),
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Lucide.Link,
                  label: 'Enter image URL',
                  onTap: () => _inputImageUrl(context),
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.person_outline,
                  label: 'Import QQ avatar',
                  onTap: () => _inputQQAvatar(context),
                ),
                if (hasCustom) ...[
                  const SizedBox(height: 8),
                  _ActionButton(
                    icon: Lucide.Trash2,
                    label: 'Delete custom avatar',
                    danger: true,
                    onTap: () => _deleteAvatar(context),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLocalImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _loading = true);
      try {
        final file = result.files.first;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();

        final relativePath = await ProviderAvatarManager.saveAvatar(
          widget.providerKey,
          bytes,
        );

        if (mounted) {
          final sp = context.read<SettingsProvider>();
          final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

          // Delete old avatar if exists
          if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
            await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
          }

          await sp.setProviderConfig(
            widget.providerKey,
            cfg.copyWith(customAvatarPath: relativePath),
          );

          if (mounted) {
            showAppSnackBar(context, message: 'Avatar saved');
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, message: 'Failed to save avatar: $e', type: NotificationType.error);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickEmoji(BuildContext context) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (ctx) => _EmojiPickerDialog(),
    );

    if (emoji != null && emoji.isNotEmpty && mounted) {
      final sp = context.read<SettingsProvider>();
      final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

      // Delete old avatar file if exists (but not emoji)
      if (cfg.customAvatarPath != null &&
          cfg.customAvatarPath!.isNotEmpty &&
          cfg.customAvatarPath!.length > 4) {
        await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
      }

      await sp.setProviderConfig(
        widget.providerKey,
        cfg.copyWith(customAvatarPath: emoji),
      );

      if (mounted) {
        showAppSnackBar(context, message: 'Avatar saved');
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _inputImageUrl(BuildContext context) async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextInputDialog(
        title: 'Image URL',
        hint: 'https://example.com/avatar.png',
      ),
    );

    if (url != null && url.trim().isNotEmpty && mounted) {
      setState(() => _loading = true);
      try {
        final response = await http.get(Uri.parse(url.trim())).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && mounted) {
          final bytes = response.bodyBytes;

          final relativePath = await ProviderAvatarManager.saveAvatar(
            widget.providerKey,
            bytes,
          );

          if (mounted) {
            final sp = context.read<SettingsProvider>();
            final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

            // Delete old avatar if exists
            if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
              await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
            }

            await sp.setProviderConfig(
              widget.providerKey,
              cfg.copyWith(customAvatarPath: relativePath),
            );

            if (mounted) {
              showAppSnackBar(context, message: 'Avatar saved');
              Navigator.of(context).pop();
            }
          }
        } else if (mounted) {
          showAppSnackBar(context, message: 'Failed to download image: HTTP ${response.statusCode}', type: NotificationType.error);
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, message: 'Failed to download image: $e', type: NotificationType.error);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteAvatar(BuildContext context) async {
    final sp = context.read<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

    if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
      // Delete file if it's not an emoji
      if (cfg.customAvatarPath!.length > 4) {
        await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
      }

      await sp.setProviderConfig(
        widget.providerKey,
        cfg.copyWith(customAvatarPath: ''),
      );

      if (mounted) {
        showAppSnackBar(context, message: 'Avatar deleted');
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _inputQQAvatar(BuildContext context) async {
    final qq = await showDialog<String>(
      context: context,
      builder: (ctx) => _QQInputDialog(),
    );

    if (qq != null && qq.trim().isNotEmpty && mounted) {
      setState(() => _loading = true);
      try {
        final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=${qq.trim()}&spec=100';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty && mounted) {
          final bytes = response.bodyBytes;

          final relativePath = await ProviderAvatarManager.saveAvatar(
            widget.providerKey,
            bytes,
          );

          if (mounted) {
            final sp = context.read<SettingsProvider>();
            final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

            // Delete old avatar if exists
            if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
              await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
            }

            await sp.setProviderConfig(
              widget.providerKey,
              cfg.copyWith(customAvatarPath: relativePath),
            );

            if (mounted) {
              showAppSnackBar(context, message: 'QQ avatar saved');
              Navigator.of(context).pop();
            }
          }
        } else if (mounted) {
          showAppSnackBar(context, message: 'Failed to download QQ avatar', type: NotificationType.error);
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, message: 'Failed to download QQ avatar: $e', type: NotificationType.error);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }
}

// ========== Helper Widgets ==========

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.danger ? cs.error : cs.onSurface;
    final bg = _hover
        ? (widget.danger
            ? cs.error.withOpacity(0.1)
            : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ),
              Icon(Lucide.ChevronRight, size: 16, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({super.key, required this.name, this.size = 22, this.customAvatarPath, this.providerKey});
  final String name;
  final double size;
  final String? customAvatarPath;
  final String? providerKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if custom avatar exists
    if (customAvatarPath != null && customAvatarPath!.isNotEmpty) {
      // Check if it's an emoji
      if (customAvatarPath!.length <= 4 && customAvatarPath!.runes.length == 1) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            customAvatarPath!,
            style: TextStyle(fontSize: size * 0.55),
          ),
        );
      }

      // Check if file exists (use FutureBuilder for async path resolution)
      return FutureBuilder<String?>(
        future: ProviderAvatarManager.getAvatarPath(customAvatarPath!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final file = File(snapshot.data!);
            if (file.existsSync()) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: FileImage(file),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }
          }
          // Fallback if file doesn't exist or not loaded yet
          return _buildFallbackAvatar(context, cs, isDark, size);
        },
      );
    }

    return _buildFallbackAvatar(context, cs, isDark, size);
  }

  Widget _buildFallbackAvatar(BuildContext context, ColorScheme cs, bool isDark, double size) {
    // Fallback to brand asset or initial (use providerKey if available)
    final lookupName = providerKey ?? name;
    final asset = BrandAssets.assetForName(lookupName);
    Widget inner;
    if (asset == null) {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.45,
        ),
      );
    } else if (asset.endsWith('.svg')) {
      inner = SvgPicture.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
    } else {
      inner = Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.10),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

// Emoji picker dialog
class _EmojiPickerDialog extends StatelessWidget {
  final List<String> _emojis = const [
    '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙',
    '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓',
    '😎', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕',
    '🙁', '☹️', '😣', '😖', '😫', '😩', '🥺', '😢', '😭',
    '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱',
    '🤔', '🤗', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬',
    '🙄', '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose Emoji',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _IconBtn(
                    icon: Lucide.X,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 9,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _emojis.length,
                  itemBuilder: (ctx, i) {
                    final emoji = _emojis[i];
                    return _EmojiButton(
                      emoji: emoji,
                      onTap: () => Navigator.of(ctx).pop(emoji),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiButton extends StatefulWidget {
  const _EmojiButton({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}

// Text input dialog
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _IconBtn(
                    icon: Lucide.X,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _SubmitButton(
                  label: 'Save',
                  onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// QQ input dialog
class _QQInputDialog extends StatefulWidget {
  @override
  State<_QQInputDialog> createState() => _QQInputDialogState();
}

class _QQInputDialogState extends State<_QQInputDialog> {
  final _ctrl = TextEditingController();
  String _value = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isValid(String s) => RegExp(r'^[0-9]{5,12}$').hasMatch(s.trim());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Import QQ Avatar',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _IconBtn(
                    icon: Lucide.X,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter QQ number (5-12 digits)',
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (v) => setState(() => _value = v),
                onSubmitted: (_) {
                  if (_isValid(_value)) Navigator.of(context).pop(_value.trim());
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _SubmitButton(
                  label: 'Import',
                  enabled: _isValid(_value),
                  onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({required this.label, required this.onTap, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.enabled
        ? (_pressed
            ? cs.primary.withOpacity(0.85)
            : _hover
                ? cs.primary.withOpacity(0.92)
                : cs.primary)
        : cs.onSurface.withOpacity(0.12);

    return MouseRegion(
      onEnter: (_) => widget.enabled ? setState(() => _hover = true) : null,
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => widget.enabled ? setState(() => _pressed = true) : null,
        onTapUp: (_) => widget.enabled ? setState(() => _pressed = false) : null,
        onTapCancel: () => widget.enabled ? setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.enabled ? cs.onPrimary : cs.onSurface.withOpacity(0.38),
            ),
          ),
        ),
      ),
    );
  }
}
