import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/preset_message.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../widgets/tactile_widgets.dart';

class PromptTab extends StatefulWidget {
  const PromptTab({required this.assistantId});
  final String assistantId;

  @override
  State<PromptTab> createState() => PromptTabState();
}

class PromptTabState extends State<PromptTab> {
  late final TextEditingController _sysCtrl;
  late final TextEditingController _tmplCtrl;
  late final FocusNode _sysFocus;
  late final FocusNode _tmplFocus;
  late final TextEditingController _presetCtrl;
  bool _showPresetInput = false;
  String _presetRole = 'user';
  final GlobalKey _presetHeaderKey = GlobalKey(debugLabel: 'presetHeader');

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _sysCtrl = TextEditingController(text: a.systemPrompt);
    _tmplCtrl = TextEditingController(text: a.messageTemplate);
    _sysFocus = FocusNode(debugLabel: 'systemPromptFocus');
    _tmplFocus = FocusNode(debugLabel: 'messageTemplateFocus');
    _presetCtrl = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant PromptTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _sysCtrl.text = a.systemPrompt;
      _tmplCtrl.text = a.messageTemplate;
    }
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _tmplCtrl.dispose();
    _sysFocus.dispose();
    _tmplFocus.dispose();
    _presetCtrl.dispose();
    super.dispose();
  }

  void _insertAtCursor(TextEditingController controller, String toInsert) {
    final text = controller.text;
    final sel = controller.selection;
    final start =
        (sel.start >= 0 && sel.start <= text.length) ? sel.start : text.length;
    final end =
        (sel.end >= 0 && sel.end <= text.length && sel.end >= start)
            ? sel.end
            : start;
    final nextText = text.replaceRange(start, end, toInsert);
    controller.value = controller.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + toInsert.length),
      composing: TextRange.empty,
    );
  }

  void _insertNewlineAtCursor() {
    _insertAtCursor(_sysCtrl, '\n');
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    ap.updateAssistant(a.copyWith(systemPrompt: _sysCtrl.text));
    setState(() {});
  }

  Widget presetCard() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = a.presetMessages;
    final isDesktop = Theme.of(context).platform == TargetPlatform.macOS || Theme.of(context).platform == TargetPlatform.linux || Theme.of(context).platform == TargetPlatform.windows;

    Widget dragWrapper({required int index, required Widget child}) {
      return isDesktop
          ? ReorderableDragStartListener(index: index, child: child)
          : ReorderableDelayedDragStartListener(index: index, child: child);
    }

    Widget headerButtons() {
      Widget makeButtons() => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HoverPillButton(
                icon: Lucide.User,
                color: cs.primary,
                label: l10n.assistantEditPresetAddUser,
                onTap: () {
                  setState(() {
                    _presetRole = 'user';
                    _presetCtrl.text = '';
                    _showPresetInput = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final ctx = _presetHeaderKey.currentContext;
                    if (ctx != null) {
                      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
                    }
                  });
                },
              ),
              HoverPillButton(
                icon: Lucide.Bot,
                color: cs.secondary,
                label: l10n.assistantEditPresetAddAssistant,
                onTap: () {
                  setState(() {
                    _presetRole = 'assistant';
                    _presetCtrl.text = '';
                    _showPresetInput = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final ctx = _presetHeaderKey.currentContext;
                    if (ctx != null) {
                      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
                    }
                  });
                },
              ),
            ],
          );

      return Container(
        key: _presetHeaderKey,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final textScale = MediaQuery.of(ctx).textScaleFactor;
            final narrow = constraints.maxWidth < 420 || textScale > 1.15;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.assistantEditPresetTitle,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  makeButtons(),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.assistantEditPresetTitle,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                makeButtons(),
              ],
            );
          },
        ),
      );
    }

    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);

    return Container(
      decoration: BoxDecoration(color: baseBg, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerButtons(),
            const SizedBox(height: 10),

            if (items.isEmpty)
              Text(l10n.assistantEditPresetEmpty, style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),

            if (items.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, anim) {
                  return AnimatedBuilder(
                    animation: anim,
                    builder: (_, __) => ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
                  );
                },
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final list = List<PresetMessage>.of(a.presetMessages);
                  final item = list.removeAt(oldIndex);
                  list.insert(newIndex, item);
                  await context.read<AssistantProvider>().updateAssistant(a.copyWith(presetMessages: list));
                },
                itemBuilder: (ctx, i) {
                  final m = items[i];
                  final card = PresetMessageCard(
                    role: m.role,
                    content: m.content,
                    onEdit: () async => _showEditPresetDialog(context, a, m),
                    onDelete: () async {
                      final list = List<PresetMessage>.of(a.presetMessages);
                      list.removeWhere((e) => e.id == m.id);
                      await context.read<AssistantProvider>().updateAssistant(a.copyWith(presetMessages: list));
                    },
                  );
                  return KeyedSubtree(
                    key: ValueKey(m.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: dragWrapper(index: i, child: card),
                    ),
                  );
                },
              ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: !_showPresetInput
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _presetCtrl,
                              minLines: 1,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: _presetRole == 'assistant' ? l10n.assistantEditPresetInputHintAssistant : l10n.assistantEditPresetInputHintUser,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.35))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                                contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              ),
                              autofocus: false,
                              onSubmitted: (_) async {
                                final text = _presetCtrl.text.trim();
                                if (text.isEmpty) return;
                                final list = List<PresetMessage>.of(a.presetMessages);
                                list.add(PresetMessage(role: _presetRole, content: text));
                                await context.read<AssistantProvider>().updateAssistant(a.copyWith(presetMessages: list));
                                if (!mounted) return;
                                setState(() {
                                  _showPresetInput = false;
                                  _presetCtrl.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IosButton(label: l10n.assistantEditEmojiDialogCancel, onTap: () { setState(() { _showPresetInput = false; _presetCtrl.clear(); }); }, filled: false, neutral: true),
                                const SizedBox(width: 8),
                                IosButton(label: l10n.assistantEditEmojiDialogSave, onTap: () async { final text = _presetCtrl.text.trim(); if (text.isEmpty) return; final list = List<PresetMessage>.of(a.presetMessages); list.add(PresetMessage(role: _presetRole, content: text)); await context.read<AssistantProvider>().updateAssistant(a.copyWith(presetMessages: list)); if (!mounted) return; setState(() { _showPresetInput = false; _presetCtrl.clear(); }); }, filled: true, neutral: false),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    Widget chips(List<String> items, void Function(String v) onPick) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in items)
              ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                onPressed: () => onPick(t),
              ),
          ],
        ),
      );
    }

    final sysVars = const [
      '{cur_date}',
      '{cur_time}',
      '{cur_datetime}',
      '{model_id}',
      '{model_name}',
      '{locale}',
      '{timezone}',
      '{system_version}',
      '{device_info}',
      '{battery_level}',
      '{nickname}',
    ];
    final tmplVars = const [
      '{{ role }}',
      '{{ message }}',
      '{{ time }}',
      '{{ date }}',
    ];

    // Helper to render link-like variable chips
    Widget linkWrap(List<String> vars, void Function(String v) onPick) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final t in vars)
              InkWell(
                onTap: () => onPick(t),
                child: Text(
                  t,
                  style: TextStyle(
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Sample preview for message template
    final now = DateTime.now();
    // final ts = zh
    //     ? DateFormat('yyyy年M月d日 a h:mm:ss', 'zh').format(now)
    //     : DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final sampleUser = l10n.assistantEditSampleUser;
    final sampleMsg = l10n.assistantEditSampleMessage;
    final sampleReply = l10n.assistantEditSampleReply;

    String processed(String tpl) {
      final t = (tpl.trim().isEmpty ? '{{ message }}' : tpl);
      // Simple replacements consistent with PromptTransformer
      final locale = Localizations.localeOf(context);
      final dateStr =
          locale.languageCode == 'zh'
              ? DateFormat('yyyy年M月d日', 'zh').format(now)
              : DateFormat('yyyy-MM-dd').format(now);
      final timeStr =
          locale.languageCode == 'zh'
              ? DateFormat('a h:mm:ss', 'zh').format(now)
              : DateFormat('HH:mm:ss').format(now);
      return t
          .replaceAll('{{ role }}', 'user')
          .replaceAll('{{ message }}', sampleMsg)
          .replaceAll('{{ time }}', timeStr)
          .replaceAll('{{ date }}', dateStr);
    }

    // System Prompt Card (no border, iOS style)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sysCard = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assistantEditSystemPromptTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sysCtrl,
              focusNode: _sysFocus,
              onChanged:
                  (v) => context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(systemPrompt: v),
                  ),
              // minLines: 1,
              maxLines: 8,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              contextMenuBuilder:
                  (BuildContext context, EditableTextState state) {
                    final items = <ContextMenuButtonItem>[...state.contextMenuButtonItems];

                    // Add insert newline option for iOS
                    if (Platform.isIOS) {
                      items.add(
                        ContextMenuButtonItem(
                          onPressed: () {
                            _insertNewlineAtCursor();
                            state.hideToolbar();
                          },
                          label: l10n.chatInputBarInsertNewline,
                        ),
                      );
                    }

                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: state.contextMenuAnchors,
                      buttonItems: items,
                    );
                  },
              decoration: InputDecoration(
                hintText: l10n.assistantEditSystemPromptHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                ),
                contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.assistantEditAvailableVariables,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            VarExplainList(
              items: [
                (l10n.assistantEditVariableDate, '{cur_date}'),
                (l10n.assistantEditVariableTime, '{cur_time}'),
                (l10n.assistantEditVariableDatetime, '{cur_datetime}'),
                (l10n.assistantEditVariableModelId, '{model_id}'),
                (l10n.assistantEditVariableModelName, '{model_name}'),
                (l10n.assistantEditVariableLocale, '{locale}'),
                (l10n.assistantEditVariableTimezone, '{timezone}'),
                (l10n.assistantEditVariableSystemVersion, '{system_version}'),
                (l10n.assistantEditVariableDeviceInfo, '{device_info}'),
                (l10n.assistantEditVariableBatteryLevel, '{battery_level}'),
                (l10n.assistantEditVariableNickname, '{nickname}'),
              ],
              onTapVar: (v) {
                _insertAtCursor(_sysCtrl, v);
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(systemPrompt: _sysCtrl.text),
                );
                // Restore focus to the input to keep cursor active
                Future.microtask(() => _sysFocus.requestFocus());
              },
            ),
          ],
        ),
      ),
    );

    // Template Card with preview (no border, iOS style)
    final tmplCard = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assistantEditMessageTemplateTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tmplCtrl,
              focusNode: _tmplFocus,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction:
                  Platform.isIOS
                      ? TextInputAction.done
                      : TextInputAction.newline,
              onSubmitted:
                  Platform.isIOS
                      ? (_) => FocusScope.of(context).unfocus()
                      : null,
              enableInteractiveSelection: true,
              contextMenuBuilder:
                  Platform.isIOS
                      ? (BuildContext context, EditableTextState state) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: state.contextMenuAnchors,
                          buttonItems: <ContextMenuButtonItem>[
                            ...state.contextMenuButtonItems,
                            ContextMenuButtonItem(
                              onPressed: () {
                                _insertAtCursor(_tmplCtrl, '\n');
                                context
                                    .read<AssistantProvider>()
                                    .updateAssistant(
                                      a.copyWith(
                                        messageTemplate: _tmplCtrl.text,
                                      ),
                                    );
                                setState(() {});
                                state.hideToolbar();
                              },
                              label: l10n.chatInputBarInsertNewline,
                            ),
                          ],
                        );
                      }
                      : null,
              onChanged:
                  (v) => context.read<AssistantProvider>().updateAssistant(
                    a.copyWith(messageTemplate: v),
                  ),
              decoration: InputDecoration(
                hintText: '{{ message }}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.assistantEditAvailableVariables,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            VarExplainList(
              items: [
                (l10n.assistantEditVariableRole, '{{ role }}'),
                (l10n.assistantEditVariableMessage, '{{ message }}'),
                (l10n.assistantEditVariableTime, '{{ time }}'),
                (l10n.assistantEditVariableDate, '{{ date }}'),
              ],
              onTapVar: (v) {
                _insertAtCursor(_tmplCtrl, v);
                context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(messageTemplate: _tmplCtrl.text),
                );
                // Restore focus to the input to keep cursor active
                Future.microtask(() => _tmplFocus.requestFocus());
              },
            ),

            const SizedBox(height: 12),
            Text(
              l10n.assistantEditPreviewTitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 6),
            // Use real chat message widgets for preview (consistent styling)
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final userMsg = ChatMessage(
                  role: 'user',
                  content: processed(_tmplCtrl.text),
                  conversationId: 'preview',
                );
                final botMsg = ChatMessage(
                  role: 'assistant',
                  content: sampleReply,
                  conversationId: 'preview',
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChatMessageWidget(
                      message: userMsg,
                      showModelIcon: false,
                      showTokenStats: false,
                    ),
                    ChatMessageWidget(
                      message: botMsg,
                      showModelIcon: false,
                      showTokenStats: false,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        sysCard,
        const SizedBox(height: 12),
        tmplCard,
        const SizedBox(height: 12),
        presetCard(),
      ],
    );
  }
}

Future<void> _showEditPresetDialog(BuildContext context, Assistant a, PresetMessage m) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final controller = TextEditingController(text: m.content);
  final platform = Theme.of(context).platform;
  final isDesktop = platform == TargetPlatform.macOS || platform == TargetPlatform.linux || platform == TargetPlatform.windows;
  Future<void> save() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final list = List<PresetMessage>.of(a.presetMessages);
    final idx = list.indexWhere((e) => e.id == m.id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(content: text);
    }
    await context.read<AssistantProvider>().updateAssistant(a.copyWith(presetMessages: list));
  }
  if (isDesktop) {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.assistantEditPresetEditDialogTitle, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                      icon: const Icon(Lucide.X, size: 18),
                      color: cs.onSurface,
                      onPressed: () => Navigator.of(ctx).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: m.role == 'assistant' ? l10n.assistantEditPresetInputHintAssistant : l10n.assistantEditPresetInputHintUser,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IosButton(label: l10n.assistantEditEmojiDialogCancel, onTap: () => Navigator.of(ctx).pop(), filled: false, neutral: true),
                    const SizedBox(width: 8),
                    IosButton(label: l10n.assistantEditEmojiDialogSave, onTap: () async { await save(); if (context.mounted) Navigator.of(ctx).pop(); }, filled: true, neutral: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      final bottom = MediaQuery.of(ctx).viewInsets.bottom;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.MessageSquare, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.assistantEditPresetEditDialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: m.role == 'assistant' ? l10n.assistantEditPresetInputHintAssistant : l10n.assistantEditPresetInputHintUser,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: IosButton(
                      label: l10n.assistantEditEmojiDialogCancel,
                      icon: Lucide.X,
                      onTap: () => Navigator.of(ctx).pop(),
                      filled: false,
                      neutral: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IosButton(
                      label: l10n.assistantEditEmojiDialogSave,
                      icon: Lucide.Check,
                      onTap: () async { await save(); if (context.mounted) Navigator.of(ctx).pop(); },
                      filled: true,
                      neutral: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class VarExplainList extends StatelessWidget {
  const VarExplainList({required this.items, required this.onTapVar});
  final List<(String, String)> items; // (label, var)
  final ValueChanged<String> onTapVar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final it in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${it.$1}: ',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.75),
                ),
              ),
              InkWell(
                onTap: () => onTapVar(it.$2),
                child: Text(
                  it.$2,
                  style: TextStyle(
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class PresetMessageCard extends StatefulWidget {
  const PresetMessageCard({required this.role, required this.content, required this.onEdit, required this.onDelete});
  final String role; // 'user' | 'assistant'
  final String content;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  State<PresetMessageCard> createState() => PresetMessageCardState();
}

class PresetMessageCardState extends State<PresetMessageCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderColor = _hover ? cs.primary.withOpacity(isDark ? 0.35 : 0.45) : cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08);
    final icon = widget.role == 'assistant' ? Lucide.Bot : Lucide.User;
    final badgeColor = widget.role == 'assistant' ? cs.secondary : cs.primary;

    final card = Container(
      decoration: BoxDecoration(color: baseBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor, width: 1.0)),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(icon, size: 18, color: badgeColor),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.content, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(0.9))),
          ),
        ),
        const SizedBox(width: 8),
        HoverIconButton(icon: Lucide.Settings2, onTap: widget.onEdit),
        const SizedBox(width: 4),
        HoverIconButton(icon: Lucide.Trash2, onTap: widget.onDelete),
      ]),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: card,
    );
  }
}

class HoverIconButton extends StatefulWidget {
  const HoverIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<HoverIconButton> createState() => HoverIconButtonState();
}

class HoverIconButtonState extends State<HoverIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hover ? cs.primary.withOpacity(0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 16, color: _hover ? cs.primary : cs.onSurface.withOpacity(0.9)),
        ),
      ),
    );
  }
}

class HoverPillButton extends StatefulWidget {
  const HoverPillButton({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  State<HoverPillButton> createState() => HoverPillButtonState();
}

class HoverPillButtonState extends State<HoverPillButton> {
  bool _hover = false;
  bool _press = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _press = true),
        onTapCancel: () => setState(() => _press = false),
        onTapUp: (_) => setState(() => _press = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_press ? 0.18 : _hover ? 0.14 : 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: widget.color),
            const SizedBox(width: 6),
            Text(widget.label, style: TextStyle(color: widget.color, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
