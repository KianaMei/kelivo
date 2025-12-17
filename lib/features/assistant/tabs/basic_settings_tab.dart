import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:characters/characters.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../../core/services/http/dio_client.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/local_image_provider.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../core/services/upload/upload_service.dart';
import '../../model/widgets/model_select_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/assistant_helpers.dart';
import '../widgets/tactile_widgets.dart';

class BasicSettingsTab extends StatefulWidget {
  const BasicSettingsTab({required this.assistantId});
  final String assistantId;

  @override
  State<BasicSettingsTab> createState() => BasicSettingsTabState();
}

class BasicSettingsTabState extends State<BasicSettingsTab> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _backgroundCtrl;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _nameCtrl = TextEditingController(text: a.name);
    _backgroundCtrl = TextEditingController(text: a.background ?? '');
  }

  @override
  void didUpdateWidget(covariant BasicSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _nameCtrl.text = a.name;
      _backgroundCtrl.text = a.background ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _backgroundCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    Widget titleDesc(String title, String? desc) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (desc != null) ...[
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ],
    );

    Widget avatarWidget({double size = 56}) {
      final bg = cs.primary.withOpacity(isDark ? 0.18 : 0.12);
      Widget inner;
      final av = a.avatar?.trim();
      Widget initial() => Text(
        (a.name.trim().isNotEmpty
            ? String.fromCharCode(a.name.trim().runes.first).toUpperCase()
            : 'A'),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      );
      if (av != null && av.isNotEmpty) {
        if (av.startsWith('http')) {
          inner = FutureBuilder<String?>(
            future: AvatarCache.getPath(av),
            builder: (ctx, snap) {
              final p = snap.data;
              if (p != null && !kIsWeb && PlatformUtils.fileExistsSync(p)) {
                return ClipOval(
                  child: Image(
                    image: localFileImage(p),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                );
              }
              if (p != null && kIsWeb && p.startsWith('data:')) {
                return ClipOval(
                  child: Image.network(
                    p,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                );
              }
              return ClipOval(
                child: Image.network(
                  av,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            },
          );
        } else if (!kIsWeb &&
            (av.startsWith('/') || av.contains(':') || av.contains('/'))) {
          inner = FutureBuilder<String?>(
            future: AssistantProvider.resolveToAbsolutePath(av),
            builder: (ctx, snap) {
              final path = snap.data;
              if (path != null && PlatformUtils.fileExistsSync(path)) {
                return ClipOval(
                  child: Image(
                    image: localFileImage(path),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                );
              }
              return initial();
            },
          );
        } else {
          inner = Text(
            av,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.42,
            ),
          );
        }
      } else {
        inner = initial();
      }
      return GestureDetector(
        onTapDown: (details) {
          final position = details.globalPosition;
          _showAvatarPicker(context, a, position);
        },
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {},
            child: CircleAvatar(
              radius: size / 2,
              backgroundColor: bg,
              child: inner,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Identity card (avatar + name) - iOS style
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
              width: 0.6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                avatarWidget(size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: InputRow(
                    label: l10n.assistantEditAssistantNameLabel,
                    controller: _nameCtrl,
                    onChanged:
                        (v) => context
                            .read<AssistantProvider>()
                            .updateAssistant(a.copyWith(name: v)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // iOS section card with all settings (without Use Assistant Avatar and Stream Output)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: iosSectionCard(
            children: [
              // Temperature - embedded slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _TemperatureSliderInline(assistant: a),
              ),
              iosDivider(context),
              // Top P - embedded slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _TopPSliderInline(assistant: a),
              ),
              iosDivider(context),
              // Context messages - embedded slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _ContextMessagesSliderInline(assistant: a),
              ),
              iosDivider(context),
              // Max tokens - embedded slider (like remote's context messages)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _MaxTokensSliderInline(assistant: a),
              ),
              iosDivider(context),
              // Use assistant avatar
              iosSwitchRow(
                context,
                icon: Lucide.User,
                label: l10n.assistantEditUseAssistantAvatarTitle,
                value: a.useAssistantAvatar,
                onChanged:
                    (v) => context.read<AssistantProvider>().updateAssistant(
                      a.copyWith(useAssistantAvatar: v),
                    ),
              ),
              iosDivider(context),
              // Stream output
              iosSwitchRow(
                context,
                icon: Lucide.Zap,
                label: l10n.assistantEditStreamOutputTitle,
                value: a.streamOutput,
                onChanged:
                    (v) => context.read<AssistantProvider>().updateAssistant(
                      a.copyWith(streamOutput: v),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Chat model card (moved down, styled like DefaultModelPage)
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
              width: 0.6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.MessageCircle, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.assistantEditChatModelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.assistantEditChatModelSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                TactileRow(
                  onTap: () async {
                    final sel = await showModelSelector(context);
                    if (sel != null) {
                      await context.read<AssistantProvider>().updateAssistant(
                        a.copyWith(
                          chatModelProvider: sel.providerKey,
                          chatModelId: sel.modelId,
                        ),
                      );
                    }
                  },
                  pressedScale: 0.98,
                  builder: (pressed) {
                    final bg =
                        isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                    final overlay =
                        isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.05);
                    final pressedBg = Color.alphaBlend(overlay, bg);
                    final l10n = AppLocalizations.of(context)!;
                    final settings = context.read<SettingsProvider>();
                    String display = l10n.assistantEditModelUseGlobalDefault;
                    String brandName = display;
                    if (a.chatModelProvider != null && a.chatModelId != null) {
                      try {
                        final cfg = settings.getProviderConfig(
                          a.chatModelProvider!,
                        );
                        final ov = cfg.modelOverrides[a.chatModelId] as Map?;
                        brandName =
                            cfg.name.isNotEmpty
                                ? cfg.name
                                : a.chatModelProvider!;
                        final mdl =
                            (ov != null &&
                                    (ov['name'] as String?)?.isNotEmpty == true)
                                ? (ov['name'] as String)
                                : a.chatModelId!;
                        display = mdl;
                      } catch (_) {
                        brandName = a.chatModelProvider ?? '';
                        display = a.chatModelId ?? '';
                      }
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: pressed ? pressedBg : bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          BrandAvatarLike(name: display, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Chat background (separate iOS card)
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
              width: 0.6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.Image, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.assistantEditChatBackgroundTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.assistantEditChatBackgroundDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                if ((a.background ?? '').isEmpty) ...[
                  // Single button when no background (full width)
                  TactileRow(
                    onTap: () => _pickBackground(context, a),
                    pressedScale: 0.98,
                    builder: (pressed) {
                      final bg =
                          isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                      final overlay =
                          isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.black.withOpacity(0.05);
                      final pressedBg = Color.alphaBlend(overlay, bg);
                      final iconColor = cs.onSurface.withOpacity(0.75);
                      final textColor = cs.onSurface.withOpacity(0.9);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: pressed ? pressedBg : bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 2.0,
                              ), // Material icon spacing
                              child: Icon(
                                Icons.image,
                                size: 18,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.assistantEditChooseImageButton,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // Two buttons when background exists
                  Row(
                    children: [
                      Expanded(
                        child: IosButton(
                          label: l10n.assistantEditChooseImageButton,
                          icon: Icons.image,
                          onTap: () => _pickBackground(context, a),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: IosButton(
                          label: l10n.assistantEditClearButton,
                          icon: Lucide.X,
                          onTap:
                              () => context
                                  .read<AssistantProvider>()
                                  .updateAssistant(
                                    a.copyWith(clearBackground: true),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
                if ((a.background ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _BackgroundPreview(path: a.background!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAvatarPicker(BuildContext context, Assistant a, Offset position) async {
    final l10n = AppLocalizations.of(context)!;
    
    // Desktop: show context menu instead of bottom sheet
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.windows || platform == TargetPlatform.macOS || platform == TargetPlatform.linux) {
      showAvatarContextMenu(context, a, position);
      return;
    }
    
    // Mobile: keep bottom sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final maxH = MediaQuery.of(ctx).size.height * 0.8;
        Widget row(String text, Future<void> Function() action) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              height: 48,
              child: IosCardPress(
                borderRadius: BorderRadius.circular(14),
                baseColor: cs.surface,
                duration: const Duration(milliseconds: 260),
                onTap: () async {
                  Haptics.light();
                  Navigator.of(ctx).pop();
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  await action();
                },
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    row(
                      l10n.assistantEditAvatarChooseImage,
                      () async => _pickLocalImage(context, a),
                    ),
                    row(l10n.assistantEditAvatarChooseEmoji, () async {
                      final emoji = await _pickEmoji(context);
                      if (emoji != null) {
                        await context.read<AssistantProvider>().updateAssistant(
                          a.copyWith(avatar: emoji),
                        );
                      }
                    }),
                    row(
                      l10n.assistantEditAvatarEnterLink,
                      () async => _inputAvatarUrl(context, a),
                    ),
                    row(
                      l10n.assistantEditAvatarImportQQ,
                      () async => _inputQQAvatar(context, a),
                    ),
                    row(l10n.assistantEditAvatarReset, () async {
                      await context.read<AssistantProvider>().updateAssistant(
                        a.copyWith(clearAvatar: true),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickBackground(BuildContext context, Assistant a) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return;
        final sp = context.read<SettingsProvider>();
        final providerKey = sp.currentModelProvider;
        final accessCode = providerKey != null ? sp.getProviderConfig(providerKey).apiKey : null;
        final url = await UploadService.uploadBytes(
          bytes: Uint8List.fromList(bytes),
          fileName: 'assistant_bg_${a.id}_${DateTime.now().millisecondsSinceEpoch}.${_extFromName(f.name)}',
          contentType: _mimeFromName(f.name),
          accessCode: accessCode,
        );
        await context.read<AssistantProvider>().updateAssistant(a.copyWith(background: url));
        return;
      }

      final path = f.path;
      if (path == null || path.isEmpty) return;
      await context.read<AssistantProvider>().updateAssistant(a.copyWith(background: path));
    } catch (_) {}
  }

  Future<void> _showTemperatureSheet(BuildContext context, Assistant a) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final value =
                    context
                        .watch<AssistantProvider>()
                        .getById(widget.assistantId)
                        ?.temperature ??
                    0.6;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Temperature',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IosSwitch(
                          value: a.temperature != null,
                          onChanged: (v) async {
                            if (v) {
                              await context
                                  .read<AssistantProvider>()
                                  .updateAssistant(
                                    a.copyWith(temperature: 0.6),
                                  );
                            } else {
                              await context
                                  .read<AssistantProvider>()
                                  .updateAssistant(
                                    a.copyWith(clearTemperature: true),
                                  );
                            }
                            // Close the bottom sheet after toggle
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (a.temperature != null) ...[
                      _SliderTileNew(
                        value: value.clamp(0.0, 2.0),
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        label: value.toStringAsFixed(2),
                        onChanged:
                            (v) => context
                                .read<AssistantProvider>()
                                .updateAssistant(a.copyWith(temperature: v)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.assistantEditTemperatureDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.assistantEditParameterDisabled,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTopPSheet(BuildContext context, Assistant a) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final value =
                    context
                        .watch<AssistantProvider>()
                        .getById(widget.assistantId)
                        ?.topP ??
                    1.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Top P',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IosSwitch(
                          value: a.topP != null,
                          onChanged: (v) async {
                            if (v) {
                              await context
                                  .read<AssistantProvider>()
                                  .updateAssistant(a.copyWith(topP: 1.0));
                            } else {
                              await context
                                  .read<AssistantProvider>()
                                  .updateAssistant(a.copyWith(clearTopP: true));
                            }
                            // Close the bottom sheet after toggle
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (a.topP != null) ...[
                      _SliderTileNew(
                        value: value.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: value.toStringAsFixed(2),
                        onChanged:
                            (v) => context
                                .read<AssistantProvider>()
                                .updateAssistant(a.copyWith(topP: v)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.assistantEditTopPDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.assistantEditParameterDisabled,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // [DEPRECATED] This bottom sheet is no longer used.
  // Context messages slider is now inline via _ContextMessagesSliderInline.
  // Future<void> _showContextMessagesSheet(
  //   BuildContext context,
  //   Assistant a,
  // ) async {
  //   final cs = Theme.of(context).colorScheme;
  //   final l10n = AppLocalizations.of(context)!;
  //   await showModalBottomSheet(
  //     context: context,
  //     backgroundColor: cs.surface,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  //     ),
  //     isScrollControlled: false,
  //     builder: (ctx) {
  //       return SafeArea(
  //         child: Padding(
  //           padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
  //           child: Builder(
  //             builder: (context) {
  //               final theme = Theme.of(context);
  //               final cs = theme.colorScheme;
  //               final isDark = theme.brightness == Brightness.dark;
  //               final value =
  //                   context
  //                       .watch<AssistantProvider>()
  //                       .getById(widget.assistantId)
  //                       ?.contextMessageSize ??
  //                   20;
  //               return Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   // Drag handle
  //                   Center(
  //                     child: Container(
  //                       width: 40,
  //                       height: 4,
  //                       decoration: BoxDecoration(
  //                         color: cs.onSurface.withOpacity(0.2),
  //                         borderRadius: BorderRadius.circular(999),
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 12),
  //                   Row(
  //                     children: [
  //                       Expanded(
  //                         child: Text(
  //                           l10n.assistantEditContextMessagesTitle,
  //                           style: const TextStyle(
  //                             fontSize: 16,
  //                             fontWeight: FontWeight.w600,
  //                           ),
  //                         ),
  //                       ),
  //                       IosSwitch(
  //                         value: a.limitContextMessages,
  //                         onChanged: (v) async {
  //                           await context
  //                               .read<AssistantProvider>()
  //                               .updateAssistant(
  //                                 a.copyWith(limitContextMessages: v),
  //                               );
  //                           // Close the bottom sheet after toggle
  //                           Navigator.of(ctx).pop();
  //                         },
  //                       ),
  //                     ],
  //                   ),
  //                   const SizedBox(height: 8),
  //                   if (a.limitContextMessages) ...[
  //                     _SliderTileNew(
  //                       value: value.toDouble().clamp(0, 256),
  //                       min: 0,
  //                       max: 256,
  //                       divisions: 64,
  //                       label: value.toString(),
  //                       onChanged:
  //                           (v) => context
  //                               .read<AssistantProvider>()
  //                               .updateAssistant(
  //                                 a.copyWith(contextMessageSize: v.round()),
  //                               ),
  //                     ),
  //                     const SizedBox(height: 6),
  //                     Text(
  //                       l10n.assistantEditContextMessagesDescription,
  //                       style: TextStyle(
  //                         fontSize: 12,
  //                         color: cs.onSurface.withOpacity(0.6),
  //                       ),
  //                     ),
  //                   ] else ...[
  //                     Padding(
  //                       padding: const EdgeInsets.symmetric(vertical: 8),
  //                       child: Text(
  //                         l10n.assistantEditParameterDisabled2,
  //                         style: TextStyle(
  //                           fontSize: 13,
  //                           color: cs.onSurface.withOpacity(0.6),
  //                         ),
  //                       ),
  //                     ),
  //                   ],
  //                 ],
  //               );
  //             },
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

}

// Inline Max Tokens Slider (styled like remote's sliders with preset chips)
class _MaxTokensSliderInline extends StatelessWidget {
  const _MaxTokensSliderInline({required this.assistant});
  final Assistant assistant;

  String _formatValue(int value, AppLocalizations l10n) {
    if (value == 0) return l10n.maxTokensSheetUnlimited;
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = context.watch<AssistantProvider>().getById(assistant.id);
    if (a == null) return const SizedBox.shrink();

    final value = a.maxTokens ?? 0;
    const maxLimit = 128000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Lucide.Hash, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.assistantEditMaxTokensTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              _formatValue(value, l10n),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SfSliderTheme(
          data: SfSliderThemeData(
            activeTrackHeight: 8,
            inactiveTrackHeight: 8,
            overlayRadius: 14,
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
            tooltipBackgroundColor: cs.primary,
            thumbColor: cs.primary,
            thumbRadius: 10,
            activeLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
            inactiveLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
          ),
          child: SfSlider(
            value: value.toDouble(),
            min: 0.0,
            max: maxLimit.toDouble(),
            interval: 16000.0,
            minorTicksPerInterval: 3,
            showTicks: true,
            showLabels: true,
            enableTooltip: true,
            tooltipShape: const SfPaddleTooltipShape(),
            labelFormatterCallback: (dynamic actualValue, String formattedText) {
              final val = (actualValue as double).round();
              if (val == 0) return l10n.maxTokensSheetUnlimited;
              if (val >= 1000) {
                return '${(val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}K';
              }
              return val.toString();
            },
            onChanged: (v) {
              final rounded = (v as double).round();
              context.read<AssistantProvider>().updateAssistant(
                a.copyWith(maxTokens: rounded),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        // Quick presets - full width responsive layout
        Column(
          children: [
            Row(
              children: [
                Expanded(child: _PresetChip(label: l10n.maxTokensSheetUnlimited, value: 0, currentValue: value, assistant: a)),
                const SizedBox(width: 8),
                Expanded(child: _PresetChip(label: '4K', value: 4000, currentValue: value, assistant: a)),
                const SizedBox(width: 8),
                Expanded(child: _PresetChip(label: '8K', value: 8000, currentValue: value, assistant: a)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _PresetChip(label: '16K', value: 16000, currentValue: value, assistant: a)),
                const SizedBox(width: 8),
                Expanded(child: _PresetChip(label: '32K', value: 32000, currentValue: value, assistant: a)),
                const SizedBox(width: 8),
                Expanded(child: _PresetChip(label: '64K', value: 64000, currentValue: value, assistant: a)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatefulWidget {
  const _PresetChip({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.assistant,
  });

  final String label;
  final int value;
  final int currentValue;
  final Assistant assistant;

  @override
  State<_PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<_PresetChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = widget.currentValue == widget.value;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          context.read<AssistantProvider>().updateAssistant(
            widget.assistant.copyWith(maxTokens: widget.value),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withOpacity(0.15)
                : (_hovered
                    ? (isDark ? Colors.white : Colors.black).withOpacity(isDark ? 0.08 : 0.05)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? cs.primary.withOpacity(0.4) : cs.onSurface.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// Temperature Slider Inline (styled like remote's implementation)
class _TemperatureSliderInline extends StatelessWidget {
  const _TemperatureSliderInline({required this.assistant});
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = context.watch<AssistantProvider>().getById(assistant.id);
    if (a == null) return const SizedBox.shrink();

    final enabled = a.temperature != null;
    final value = (a.temperature ?? 1.0).clamp(0.0, 2.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Lucide.Thermometer, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Temperature',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            if (enabled)
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            if (!enabled)
              Text(
                l10n.assistantEditParameterDisabled,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
              ),
            const SizedBox(width: 8),
            IosSwitch(
              value: enabled,
              onChanged: (v) {
                if (v) {
                  context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(temperature: 1.0),
                  );
                } else {
                  context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(clearTemperature: true),
                  );
                }
              },
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 8,
              inactiveTrackHeight: 8,
              overlayRadius: 14,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
              tooltipBackgroundColor: cs.primary,
              thumbColor: cs.primary,
              thumbRadius: 10,
              activeLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
              inactiveLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            ),
            child: SfSlider(
              value: value,
              min: 0.0,
              max: 2.0,
              interval: 0.5,
              minorTicksPerInterval: 4,
              showTicks: true,
              showLabels: true,
              enableTooltip: true,
              tooltipShape: const SfPaddleTooltipShape(),
              labelFormatterCallback: (dynamic actualValue, String formattedText) {
                return (actualValue as double).toStringAsFixed(1);
              },
              onChanged: (v) {
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(temperature: v as double),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// Context Messages Slider Inline (styled like remote's implementation)
class _ContextMessagesSliderInline extends StatelessWidget {
  const _ContextMessagesSliderInline({required this.assistant});
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = context.watch<AssistantProvider>().getById(assistant.id);
    if (a == null) return const SizedBox.shrink();

    final value = a.contextMessageSize.clamp(0, 512);
    final enabled = a.limitContextMessages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Lucide.MessagesSquare, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.assistantEditContextMessagesTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            if (enabled)
              Text(
                value.toString(),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            if (!enabled)
              Text(
                l10n.assistantEditParameterDisabled2,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
              ),
            const SizedBox(width: 8),
            IosSwitch(
              value: enabled,
              onChanged: (v) {
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(limitContextMessages: v),
                );
              },
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 8,
              inactiveTrackHeight: 8,
              overlayRadius: 14,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
              tooltipBackgroundColor: cs.primary,
              thumbColor: cs.primary,
              thumbRadius: 10,
              activeLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
              inactiveLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            ),
            child: SfSlider(
              value: value.toDouble(),
              min: 0.0,
              max: 512.0,
              interval: 64.0,
              minorTicksPerInterval: 3,
              showTicks: true,
              showLabels: true,
              enableTooltip: true,
              tooltipShape: const SfPaddleTooltipShape(),
              labelFormatterCallback: (dynamic actualValue, String formattedText) {
                return (actualValue as double).round().toString();
              },
              onChanged: (v) {
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(contextMessageSize: (v as double).round()),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// Top P Slider Inline (styled like remote's implementation)
class _TopPSliderInline extends StatelessWidget {
  const _TopPSliderInline({required this.assistant});
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = context.watch<AssistantProvider>().getById(assistant.id);
    if (a == null) return const SizedBox.shrink();

    final enabled = a.topP != null;
    final value = (a.topP ?? 1.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Lucide.Wand2, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Top P',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            if (enabled)
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            if (!enabled)
              Text(
                l10n.assistantEditParameterDisabled,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
              ),
            const SizedBox(width: 8),
            IosSwitch(
              value: enabled,
              onChanged: (v) {
                if (v) {
                  context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(topP: 1.0),
                  );
                } else {
                  context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(clearTopP: true),
                  );
                }
              },
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 8,
              inactiveTrackHeight: 8,
              overlayRadius: 14,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
              tooltipBackgroundColor: cs.primary,
              thumbColor: cs.primary,
              thumbRadius: 10,
              activeLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
              inactiveLabelStyle: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            ),
            child: SfSlider(
              value: value,
              min: 0.0,
              max: 1.0,
              interval: 0.2,
              minorTicksPerInterval: 3,
              showTicks: true,
              showLabels: true,
              enableTooltip: true,
              tooltipShape: const SfPaddleTooltipShape(),
              labelFormatterCallback: (dynamic actualValue, String formattedText) {
                return (actualValue as double).toStringAsFixed(1);
              },
              onChanged: (v) {
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(topP: v as double),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// Max Tokens Sheet for Assistant Settings (with slider)
class _MaxTokensSheetForAssistant extends StatefulWidget {
  const _MaxTokensSheetForAssistant({required this.assistant});
  final Assistant assistant;

  @override
  State<_MaxTokensSheetForAssistant> createState() =>
      _MaxTokensSheetForAssistantState();
}

class _MaxTokensSheetForAssistantState
    extends State<_MaxTokensSheetForAssistant> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.assistant.maxTokens ?? 0;
  }

  int _getMaxLimit() {
    final settings = context.read<SettingsProvider>();
    final providerKey =
        widget.assistant.chatModelProvider ?? settings.currentModelProvider;
    final modelId = widget.assistant.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) return 128000;

    final cfg = settings.getProviderConfig(providerKey);
    if (cfg == null) return 128000;

    final kind = ProviderConfig.classify(
      cfg.id,
      explicitType: cfg.providerType,
    );

    if (kind == ProviderKind.claude) {
      return 64000;
    } else if (kind == ProviderKind.google) {
      return 65535;
    } else {
      return 128000;
    }
  }

  void _updateValue(int newValue) {
    setState(() => _value = newValue);
    context.read<AssistantProvider>().updateAssistant(
      widget.assistant.copyWith(maxTokens: newValue),
    );
  }

  String _formatValue(int value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == 0) {
      return l10n.maxTokensSheetUnlimited;
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    } else {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    final maxLimit = _getMaxLimit();

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Lucide.FileText, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.maxTokensSheetTitle,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Current value display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.maxTokensSheetCurrentValue,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        _formatValue(_value),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.primary.withOpacity(0.2),
                      thumbColor: cs.primary,
                      overlayColor: cs.primary.withOpacity(0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _value.toDouble(),
                      min: 0,
                      max: maxLimit.toDouble(),
                      divisions: maxLimit ~/ 1000,
                      onChanged: (v) {
                        Haptics.light();
                        _updateValue(v.round());
                      },
                    ),
                  ),
                ),

                // Range labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.maxTokensSheetUnlimited,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        _formatValue(maxLimit),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.maxTokensSheetDescription(_formatValue(maxLimit)),
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.6),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Quick presets
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PresetChipForAssistant(
                        label: l10n.maxTokensSheetUnlimited,
                        value: 0,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(0);
                        },
                      ),
                      _PresetChipForAssistant(
                        label: '4K',
                        value: 4000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(4000);
                        },
                      ),
                      _PresetChipForAssistant(
                        label: '8K',
                        value: 8000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(8000);
                        },
                      ),
                      _PresetChipForAssistant(
                        label: '16K',
                        value: 16000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(16000);
                        },
                      ),
                      _PresetChipForAssistant(
                        label: '32K',
                        value: 32000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(32000);
                        },
                      ),
                      if (maxLimit >= 64000)
                        _PresetChipForAssistant(
                          label: '64K',
                          value: 64000,
                          currentValue: _value,
                          onTap: () {
                            Haptics.light();
                            _updateValue(64000);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChipForAssistant extends StatelessWidget {
  const _PresetChipForAssistant({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.onTap,
  });

  final String label;
  final int value;
  final int currentValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = currentValue == value;

    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      baseColor: isSelected ? cs.primary.withOpacity(0.12) : cs.surface,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}

class _BackgroundPreview extends StatefulWidget {
  const _BackgroundPreview({required this.path});
  final String path;

  @override
  State<_BackgroundPreview> createState() => _BackgroundPreviewState();
}

class _BackgroundPreviewState extends State<_BackgroundPreview> {
  Size? _size;

  @override
  void initState() {
    super.initState();
    _resolveSize();
  }

  @override
  void didUpdateWidget(covariant _BackgroundPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _size = null;
      _resolveSize();
    }
  }

  Future<void> _resolveSize() async {
    try {
      if (widget.path.startsWith('http')) {
        // Skip network size probe; render with a sensible max height
        setState(() => _size = null);
        return;
      }
      if (kIsWeb) {
        setState(() => _size = null);
        return;
      }
      final fixed = SandboxPathResolver.fix(widget.path);
      final bytes = await PlatformUtils.readFileBytes(fixed);
      if (bytes == null || bytes.isEmpty) {
        setState(() => _size = null);
        return;
      }
      final img = await decodeImageFromList(Uint8List.fromList(bytes));
      final s = Size(img.width.toDouble(), img.height.toDouble());
      if (mounted) setState(() => _size = s);
    } catch (_) {
      if (mounted) setState(() => _size = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNetwork = widget.path.startsWith('http');
    final imageWidget =
        isNetwork
            ? Image.network(widget.path, fit: BoxFit.contain)
            : (kIsWeb
                ? const SizedBox.shrink()
                : Image(
                  image: localFileImage(SandboxPathResolver.fix(widget.path)),
                  fit: BoxFit.contain,
                ));
    // When size known, maintain aspect ratio; otherwise cap the height to avoid overflow
    if (_size != null && _size!.width > 0 && _size!.height > 0) {
      final ratio = _size!.width / _size!.height;
      return SizedBox(
        width: double.infinity,
        child: AspectRatio(aspectRatio: ratio, child: imageWidget),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 280,
        minHeight: 100,
        minWidth: double.infinity,
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 400, height: 240, child: imageWidget),
      ),
    );
  }
}

class _SliderTileNew extends StatelessWidget {
  const _SliderTileNew({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final active = cs.primary;
    final inactive = cs.onSurface.withOpacity(isDark ? 0.25 : 0.20);
    final double clamped = value.clamp(min, max);
    final double? step =
        (divisions != null && divisions! > 0) ? (max - min) / divisions! : null;
    // Compute a readable major interval and minor tick count
    final total = (max - min).abs();
    double interval;
    if (total <= 0) {
      interval = 1;
    } else if ((divisions ?? 0) <= 20) {
      interval = total / 4; // up to 5 major ticks inc endpoints
    } else if ((divisions ?? 0) <= 50) {
      interval = total / 5;
    } else {
      interval = total / 8;
    }
    if (interval <= 0) interval = 1;
    final int majorCount = (total / interval).round().clamp(1, 10);
    int minor = 0;
    if (step != null && step > 0) {
      // Ensure minor ticks align with the chosen step size
      minor = ((interval / step) - 1).round();
      if (minor < 0) minor = 0;
      if (minor > 8) minor = 8;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 8,
                  inactiveTrackHeight: 8,
                  overlayRadius: 14,
                  activeTrackColor: active,
                  inactiveTrackColor: inactive,
                  // Waterdrop tooltip uses theme primary background with onPrimary text
                  tooltipBackgroundColor: cs.primary,
                  tooltipTextStyle: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  thumbStrokeColor: Colors.transparent,
                  thumbStrokeWidth: 0,
                  activeTickColor: cs.onSurface.withOpacity(
                    isDark ? 0.45 : 0.35,
                  ),
                  inactiveTickColor: cs.onSurface.withOpacity(
                    isDark ? 0.30 : 0.25,
                  ),
                  activeMinorTickColor: cs.onSurface.withOpacity(
                    isDark ? 0.34 : 0.28,
                  ),
                  inactiveMinorTickColor: cs.onSurface.withOpacity(
                    isDark ? 0.24 : 0.20,
                  ),
                ),
                child: SfSlider(
                  value: clamped,
                  min: min,
                  max: max,
                  stepSize: step,
                  enableTooltip: true,
                  // Show the paddle tooltip only while interacting
                  shouldAlwaysShowTooltip: false,
                  showTicks: true,
                  showLabels: true,
                  interval: interval,
                  minorTicksPerInterval: minor,
                  activeColor: active,
                  inactiveColor: inactive,
                  tooltipTextFormatterCallback: (actual, text) => label,
                  tooltipShape: const SfPaddleTooltipShape(),
                  labelFormatterCallback: (actual, formattedText) {
                    // Prefer integers for wide ranges, keep 2 decimals for 0..1
                    if (total <= 2.0) return actual.toStringAsFixed(2);
                    if (actual == actual.roundToDouble())
                      return actual.toStringAsFixed(0);
                    return actual.toStringAsFixed(1);
                  },
                  thumbIcon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      boxShadow:
                          isDark
                              ? []
                              : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                    ),
                  ),
                  onChanged:
                      (v) => onChanged(v is num ? v.toDouble() : (v as double)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ValuePill(text: label),
          ],
        ),
        // Remove explicit min/max captions since ticks already indicate range
      ],
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withOpacity(isDark ? 0.28 : 0.22)),
        boxShadow: isDark ? [] : AppShadows.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

extension _AssistantAvatarActions on BasicSettingsTabState {
  Future<String?> _pickEmoji(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    String value = '';
    bool validGrapheme(String s) {
      final trimmed = s.characters.take(1).toString().trim();
      return trimmed.isNotEmpty && trimmed == s.trim();
    }

    final List<String> quick = const [
      '😀',
      '😁',
      '😂',
      '🤣',
      '😃',
      '😄',
      '😅',
      '😊',
      '😍',
      '😘',
      '😗',
      '😙',
      '😚',
      '🙂',
      '🤗',
      '🤩',
      '🫶',
      '🤝',
      '👍',
      '👎',
      '👋',
      '🙏',
      '💪',
      '🔥',
      '✨',
      '🌟',
      '💡',
      '🎉',
      '🎊',
      '🎈',
      '🌈',
      '☀️',
      '🌙',
      '⭐',
      '⚡',
      '☁️',
      '❄️',
      '🌧️',
      '🍎',
      '🍊',
      '🍋',
      '🍉',
      '🍇',
      '🍓',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥝',
      '🍅',
      '🥕',
      '🌽',
      '🍞',
      '🧀',
      '🍔',
      '🍟',
      '🍕',
      '🌮',
      '🌯',
      '🍣',
      '🍜',
      '🍰',
      '🍪',
      '🍩',
      '🍫',
      '🍻',
      '☕',
      '🧋',
      '🥤',
      '⚽',
      '🏀',
      '🏈',
      '🎾',
      '🏐',
      '🎮',
      '🎧',
      '🎸',
      '🎹',
      '🎺',
      '📚',
      '✏️',
      '💼',
      '💻',
      '🖥️',
      '📱',
      '🛩️',
      '✈️',
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🚀',
      '🛰️',
      '🧠',
      '🫀',
      '💊',
      '🩺',
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        value.isEmpty
                            ? '🙂'
                            : value.characters.take(1).toString(),
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (v) => setLocal(() => value = v),
                      onSubmitted: (_) {
                        if (validGrapheme(value))
                          Navigator.of(
                            ctx,
                          ).pop(value.characters.take(1).toString());
                      },
                      decoration: InputDecoration(
                        hintText: l10n.assistantEditEmojiDialogHint,
                        filled: true,
                        fillColor:
                            Theme.of(ctx).brightness == Brightness.dark
                                ? Colors.white10
                                : const Color(0xFFF2F3F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.primary.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: quick.length,
                        itemBuilder: (c, i) {
                          final e = quick[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(ctx).pop(e),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.assistantEditEmojiDialogCancel),
                ),
                TextButton(
                  onPressed:
                      validGrapheme(value)
                          ? () => Navigator.of(
                            ctx,
                          ).pop(value.characters.take(1).toString())
                          : null,
                  child: Text(
                    l10n.assistantEditEmojiDialogSave,
                    style: TextStyle(
                      color:
                          validGrapheme(value)
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.38),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _inputAvatarUrl(BuildContext context, Assistant a) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        bool valid(String s) =>
            s.trim().startsWith('http://') || s.trim().startsWith('https://');
        String value = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditImageUrlDialogTitle),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditImageUrlDialogHint,
                  filled: true,
                  fillColor:
                      Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                  ),
                ),
                onChanged: (v) => setLocal(() => value = v),
                onSubmitted: (_) {
                  if (valid(value)) Navigator.of(ctx).pop(true);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.assistantEditImageUrlDialogCancel),
                ),
                TextButton(
                  onPressed:
                      valid(value) ? () => Navigator.of(ctx).pop(true) : null,
                  child: Text(
                    l10n.assistantEditImageUrlDialogSave,
                    style: TextStyle(
                      color:
                          valid(value)
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.38),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
        await context.read<AssistantProvider>().updateAssistant(
          a.copyWith(avatar: url),
        );
      }
    }
  }

  Future<void> _inputQQAvatar(BuildContext context, Assistant a) async {
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditQQAvatarDialogTitle),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditQQAvatarDialogHint,
                  filled: true,
                  fillColor:
                      Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                  ),
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
                      final url =
                          'https://q2.qlogo.cn/headimg_dl?dst_uin=' +
                          qq +
                          '&spec=100';
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
                          await context
                              .read<AssistantProvider>()
                              .updateAssistant(a.copyWith(avatar: url));
                          applied = true;
                          break;
                        }
                      } catch (_) {}
                    }
                    if (applied) {
                      if (Navigator.of(ctx).canPop())
                        Navigator.of(ctx).pop(false);
                    } else {
                      showAppSnackBar(
                        context,
                        message: l10n.assistantEditQQAvatarFailedMessage,
                        type: NotificationType.error,
                      );
                    }
                  },
                  child: Text(l10n.assistantEditQQAvatarRandomButton),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.assistantEditQQAvatarDialogCancel),
                    ),
                    TextButton(
                      onPressed:
                          valid(value)
                              ? () => Navigator.of(ctx).pop(true)
                              : null,
                      child: Text(
                        l10n.assistantEditQQAvatarDialogSave,
                        style: TextStyle(
                          color:
                              valid(value)
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.38),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
        final url =
            'https://q2.qlogo.cn/headimg_dl?dst_uin=' + qq + '&spec=100';
        await context.read<AssistantProvider>().updateAssistant(
          a.copyWith(avatar: url),
        );
      }
    }
  }

  Future<void> _pickLocalImage(BuildContext context, Assistant a) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (!context.mounted) return;
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return;
        final sp = context.read<SettingsProvider>();
        final providerKey = sp.currentModelProvider;
        final accessCode = providerKey != null ? sp.getProviderConfig(providerKey).apiKey : null;
        final url = await UploadService.uploadBytes(
          bytes: Uint8List.fromList(bytes),
          fileName: 'assistant_avatar_${a.id}_${DateTime.now().millisecondsSinceEpoch}.${_extFromName(f.name)}',
          contentType: _mimeFromName(f.name),
          accessCode: accessCode,
        );
        await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: url));
        return;
      }

      final path = f.path;
      if (path == null || path.isEmpty) {
        await _inputAvatarUrl(context, a);
        return;
      }
      await context.read<AssistantProvider>().updateAssistant(a.copyWith(avatar: path));
      return;
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGalleryErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context, a);
      return;
    } catch (_) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGeneralErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context, a);
      return;
    }
  }

  String _extFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/*';
  }
}
