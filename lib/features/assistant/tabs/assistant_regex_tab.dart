import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/assistant_regex.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../widgets/tactile_widgets.dart';

/// Regex rules management tab for assistant settings.
class AssistantRegexTab extends StatefulWidget {
  const AssistantRegexTab({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexTab> createState() => _AssistantRegexTabState();
}

class _AssistantRegexTabState extends State<AssistantRegexTab> {
  void _onReorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    if (newIndex > oldIndex) newIndex -= 1;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _toggleRule(AssistantRegex rule, bool enabled) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = assistant.regexRules.map((r) {
      if (r.id == rule.id) return r.copyWith(enabled: enabled);
      return r;
    }).toList();
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _deleteRule(AssistantRegex rule) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules)
      ..removeWhere((r) => r.id == rule.id);
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    final data = await _showRegexEditor(context, rule: rule);
    if (data == null || !mounted) return;

    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;

    final list = List<AssistantRegex>.of(assistant.regexRules);
    final updated = AssistantRegex(
      id: rule?.id ?? const Uuid().v4(),
      name: data.name,
      pattern: data.pattern,
      replacement: data.replacement,
      scopes: data.scopes,
      visualOnly: data.visualOnly,
      enabled: rule?.enabled ?? true,
    );

    if (rule == null) {
      list.add(updated);
    } else {
      final idx = list.indexWhere((r) => r.id == rule.id);
      if (idx == -1) {
        list.add(updated);
      } else {
        list[idx] = updated;
      }
    }
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assistant = context.watch<AssistantProvider>().getById(widget.assistantId);
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;

    // Empty state
    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Lucide.ArrowLeftRight, size: 56, color: cs.primary.withOpacity(0.6)),
              const SizedBox(height: 16),
              Text(
                l10n.assistantEditRegexDescription,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 24),
              IosButton(
                label: l10n.assistantEditAddRegexButton,
                icon: Lucide.Plus,
                onTap: () => _addOrEdit(),
                filled: true,
                neutral: false,
              ),
            ],
          ),
        ),
      );
    }

    // Rules list with floating add button
    return Stack(
      children: [
        ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: rules.length,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOut.transform(animation.value);
                return Transform.scale(scale: 0.98 + 0.02 * t, child: child);
              },
            );
          },
          onReorder: _onReorder,
          itemBuilder: (context, index) {
            final rule = rules[index];
            return KeyedSubtree(
              key: ValueKey('regex-${rule.id}'),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RegexRuleCard(
                    rule: rule,
                    onTap: () => _addOrEdit(rule: rule),
                    onDelete: () => _deleteRule(rule),
                    onToggle: (v) => _toggleRule(rule, v),
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: Center(
            child: _FloatingAddButton(onTap: () => _addOrEdit()),
          ),
        ),
      ],
    );
  }
}

/// Desktop pane version for assistant regex management.
class AssistantRegexDesktopPane extends StatefulWidget {
  const AssistantRegexDesktopPane({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexDesktopPane> createState() => _AssistantRegexDesktopPaneState();
}

class _AssistantRegexDesktopPaneState extends State<AssistantRegexDesktopPane> {
  void _onReorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    if (newIndex > oldIndex) newIndex -= 1;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _toggleRule(AssistantRegex rule, bool enabled) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = assistant.regexRules.map((r) {
      if (r.id == rule.id) return r.copyWith(enabled: enabled);
      return r;
    }).toList();
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _deleteRule(AssistantRegex rule) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules)
      ..removeWhere((r) => r.id == rule.id);
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    final data = await _showRegexEditor(context, rule: rule);
    if (data == null || !mounted) return;

    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;

    final list = List<AssistantRegex>.of(assistant.regexRules);
    final updated = AssistantRegex(
      id: rule?.id ?? const Uuid().v4(),
      name: data.name,
      pattern: data.pattern,
      replacement: data.replacement,
      scopes: data.scopes,
      visualOnly: data.visualOnly,
      enabled: rule?.enabled ?? true,
    );

    if (rule == null) {
      list.add(updated);
    } else {
      final idx = list.indexWhere((r) => r.id == rule.id);
      if (idx == -1) {
        list.add(updated);
      } else {
        list[idx] = updated;
      }
    }
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assistant = context.watch<AssistantProvider>().getById(widget.assistantId);
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with title and add button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.assistantEditPageRegexTab,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.assistantEditRegexDescription,
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.65)),
                    ),
                  ],
                ),
              ),
              TactileRow(
                onTap: () => _addOrEdit(),
                pressedScale: 0.97,
                builder: (pressed) {
                  final color = pressed ? cs.primary.withOpacity(0.7) : cs.primary;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Plus, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          l10n.assistantEditAddRegexButton,
                          style: TextStyle(color: color, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // Rules list or empty state
        Expanded(
          child: rules.isEmpty
              ? Center(
                  child: Text(
                    l10n.assistantEditRegexDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6)),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: rules.length,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final t = Curves.easeOut.transform(animation.value);
                        return Transform.scale(scale: 0.985 + 0.015 * t, child: child);
                      },
                    );
                  },
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    return KeyedSubtree(
                      key: ValueKey('regex-desktop-${rule.id}'),
                      child: ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RegexRuleCard(
                            rule: rule,
                            onTap: () => _addOrEdit(rule: rule),
                            onDelete: () => _deleteRule(rule),
                            onToggle: (v) => _toggleRule(rule, v),
                            isDesktop: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Rule card widget displaying regex rule info.
class _RegexRuleCard extends StatefulWidget {
  const _RegexRuleCard({
    required this.rule,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
    this.isDesktop = false,
  });

  final AssistantRegex rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final bool isDesktop;

  @override
  State<_RegexRuleCard> createState() => _RegexRuleCardState();
}

class _RegexRuleCardState extends State<_RegexRuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderBase = cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06);
    final borderColor = widget.isDesktop && _hovered ? cs.primary.withOpacity(0.55) : borderBase;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TactileRow(
        onTap: widget.onTap,
        pressedScale: 0.98,
        builder: (pressed) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 0.7),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.rule.name.isEmpty ? l10n.assistantRegexUntitled : widget.rule.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IosSwitch(
                      value: widget.rule.enabled,
                      onChanged: widget.onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _buildScopePills(context),
                      ),
                    ),
                    TactileRow(
                      onTap: widget.onDelete,
                      pressedScale: 0.95,
                      builder: (pressed) {
                        final color = pressed ? cs.error.withOpacity(0.7) : cs.error;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Lucide.Trash2, size: 16, color: color),
                            const SizedBox(width: 6),
                            Text(
                              l10n.assistantRegexDeleteButton,
                              style: TextStyle(color: color, fontWeight: FontWeight.w700),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildScopePills(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pills = <String>[];

    if (widget.rule.scopes.contains(AssistantRegexScope.user)) {
      pills.add(l10n.assistantRegexScopeUser);
    }
    if (widget.rule.scopes.contains(AssistantRegexScope.assistant)) {
      pills.add(l10n.assistantRegexScopeAssistant);
    }
    if (widget.rule.visualOnly) {
      pills.add(l10n.assistantRegexScopeVisualOnly);
    }

    return pills
        .map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.primary.withOpacity(0.35)),
              ),
              child: Text(
                p,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            ))
        .toList();
  }
}

/// Floating add button with glass effect.
class _FloatingAddButton extends StatefulWidget {
  const _FloatingAddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_FloatingAddButton> createState() => _FloatingAddButtonState();
}

class _FloatingAddButtonState extends State<_FloatingAddButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassBase = isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.06);
    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.10 : 0.10);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tileColor,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Center(child: Icon(Lucide.Plus, size: 18, color: cs.primary)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regex Editor (Bottom Sheet for mobile, Dialog for desktop)
// ─────────────────────────────────────────────────────────────────────────────

class _RegexFormData {
  const _RegexFormData({
    required this.name,
    required this.pattern,
    required this.replacement,
    required this.scopes,
    required this.visualOnly,
  });
  final String name;
  final String pattern;
  final String replacement;
  final List<AssistantRegexScope> scopes;
  final bool visualOnly;
}

Future<_RegexFormData?> _showRegexEditor(BuildContext context, {AssistantRegex? rule}) async {
  final platform = Theme.of(context).platform;
  final isDesktop = platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows;
  return isDesktop ? _showRegexDialog(context, rule: rule) : _showRegexBottomSheet(context, rule: rule);
}

Future<_RegexFormData?> _showRegexBottomSheet(BuildContext context, {AssistantRegex? rule}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final nameCtrl = TextEditingController(text: rule?.name ?? '');
  final patternCtrl = TextEditingController(text: rule?.pattern ?? '');
  final replacementCtrl = TextEditingController(text: rule?.replacement ?? '');
  final Set<AssistantRegexScope> scopes = {...(rule?.scopes ?? <AssistantRegexScope>[AssistantRegexScope.user])};
  bool visualOnly = rule?.visualOnly ?? false;

  final result = await showModalBottomSheet<_RegexFormData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            final name = nameCtrl.text.trim();
            final pattern = patternCtrl.text.trim();
            if (name.isEmpty || pattern.isEmpty || scopes.isEmpty) {
              showAppSnackBar(ctx, message: l10n.assistantRegexValidationError, type: NotificationType.warning);
              return;
            }
            try {
              RegExp(pattern);
            } catch (_) {
              showAppSnackBar(ctx, message: l10n.assistantRegexInvalidPattern, type: NotificationType.warning);
              return;
            }
            Navigator.of(ctx).pop(_RegexFormData(
              name: name,
              pattern: pattern,
              replacement: replacementCtrl.text,
              scopes: scopes.toList(),
              visualOnly: visualOnly,
            ));
          }

          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          final maxHeight = MediaQuery.of(ctx).size.height * 0.9;

          return SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Row(
                          children: [
                            TactileIconButton(
                              icon: Lucide.X,
                              size: 20,
                              color: cs.onSurface.withOpacity(0.7),
                              onTap: () => Navigator.of(ctx).maybePop(),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  rule == null ? l10n.assistantRegexAddTitle : l10n.assistantRegexEditTitle,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            TactileRow(
                              onTap: submit,
                              builder: (pressed) {
                                final color = pressed ? cs.primary.withOpacity(0.7) : cs.primary;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    rule == null ? l10n.assistantRegexAddAction : l10n.assistantRegexSaveAction,
                                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Form fields
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RegexTextField(controller: nameCtrl, label: l10n.assistantRegexNameLabel, autofocus: true),
                            const SizedBox(height: 12),
                            _RegexTextField(controller: patternCtrl, label: l10n.assistantRegexPatternLabel),
                            const SizedBox(height: 12),
                            _RegexTextField(
                              controller: replacementCtrl,
                              label: l10n.assistantRegexReplacementLabel,
                              multiline: true,
                            ),
                            const SizedBox(height: 16),
                            Text(l10n.assistantRegexScopeLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeUser,
                                  selected: scopes.contains(AssistantRegexScope.user),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(AssistantRegexScope.user)) {
                                        scopes.remove(AssistantRegexScope.user);
                                      } else {
                                        scopes.add(AssistantRegexScope.user);
                                      }
                                    });
                                  },
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeAssistant,
                                  selected: scopes.contains(AssistantRegexScope.assistant),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(AssistantRegexScope.assistant)) {
                                        scopes.remove(AssistantRegexScope.assistant);
                                      } else {
                                        scopes.add(AssistantRegexScope.assistant);
                                      }
                                    });
                                  },
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeVisualOnly,
                                  selected: visualOnly,
                                  onTap: () => setState(() => visualOnly = !visualOnly),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  nameCtrl.dispose();
  patternCtrl.dispose();
  replacementCtrl.dispose();
  return result;
}

Future<_RegexFormData?> _showRegexDialog(BuildContext context, {AssistantRegex? rule}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final nameCtrl = TextEditingController(text: rule?.name ?? '');
  final patternCtrl = TextEditingController(text: rule?.pattern ?? '');
  final replacementCtrl = TextEditingController(text: rule?.replacement ?? '');
  final Set<AssistantRegexScope> scopes = {...(rule?.scopes ?? <AssistantRegexScope>[AssistantRegexScope.user])};
  bool visualOnly = rule?.visualOnly ?? false;

  final result = await showDialog<_RegexFormData>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              final name = nameCtrl.text.trim();
              final pattern = patternCtrl.text.trim();
              if (name.isEmpty || pattern.isEmpty || scopes.isEmpty) {
                showAppSnackBar(ctx, message: l10n.assistantRegexValidationError, type: NotificationType.warning);
                return;
              }
              try {
                RegExp(pattern);
              } catch (_) {
                showAppSnackBar(ctx, message: l10n.assistantRegexInvalidPattern, type: NotificationType.warning);
                return;
              }
              Navigator.of(ctx).pop(_RegexFormData(
                name: name,
                pattern: pattern,
                replacement: replacementCtrl.text,
                scopes: scopes.toList(),
                visualOnly: visualOnly,
              ));
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                rule == null ? l10n.assistantRegexAddTitle : l10n.assistantRegexEditTitle,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ),
                            TactileIconButton(
                              icon: Lucide.X,
                              size: 18,
                              color: cs.onSurface.withOpacity(0.7),
                              onTap: () => Navigator.of(ctx).maybePop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Form
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RegexTextField(controller: nameCtrl, label: l10n.assistantRegexNameLabel, autofocus: true),
                            const SizedBox(height: 12),
                            _RegexTextField(controller: patternCtrl, label: l10n.assistantRegexPatternLabel),
                            const SizedBox(height: 12),
                            _RegexTextField(
                              controller: replacementCtrl,
                              label: l10n.assistantRegexReplacementLabel,
                              multiline: true,
                            ),
                            const SizedBox(height: 16),
                            Text(l10n.assistantRegexScopeLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeUser,
                                  selected: scopes.contains(AssistantRegexScope.user),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(AssistantRegexScope.user)) {
                                        scopes.remove(AssistantRegexScope.user);
                                      } else {
                                        scopes.add(AssistantRegexScope.user);
                                      }
                                    });
                                  },
                                  isDesktop: true,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeAssistant,
                                  selected: scopes.contains(AssistantRegexScope.assistant),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(AssistantRegexScope.assistant)) {
                                        scopes.remove(AssistantRegexScope.assistant);
                                      } else {
                                        scopes.add(AssistantRegexScope.assistant);
                                      }
                                    });
                                  },
                                  isDesktop: true,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeVisualOnly,
                                  selected: visualOnly,
                                  onTap: () => setState(() => visualOnly = !visualOnly),
                                  isDesktop: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Footer buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IosButton(
                            label: l10n.assistantRegexCancelButton,
                            onTap: () => Navigator.of(ctx).maybePop(),
                            filled: false,
                            neutral: true,
                          ),
                          const SizedBox(width: 10),
                          IosButton(
                            label: rule == null ? l10n.assistantRegexAddAction : l10n.assistantRegexSaveAction,
                            onTap: submit,
                            filled: true,
                            neutral: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  nameCtrl.dispose();
  patternCtrl.dispose();
  replacementCtrl.dispose();
  return result;
}

/// Styled text field for regex editor.
class _RegexTextField extends StatelessWidget {
  const _RegexTextField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.multiline = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 1 : 1,
      maxLines: multiline ? null : 1,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
        ),
      ),
    );
  }
}

/// Scope selection card widget.
class _ScopeChoiceCard extends StatefulWidget {
  const _ScopeChoiceCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isDesktop = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDesktop;

  @override
  State<_ScopeChoiceCard> createState() => _ScopeChoiceCardState();
}

class _ScopeChoiceCardState extends State<_ScopeChoiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.selected ? cs.primary.withOpacity(0.16) : (isDark ? Colors.white10 : const Color(0xFFF2F3F5));
    final borderBase = widget.selected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(isDark ? 0.14 : 0.12);
    final borderColor = (widget.isDesktop && _hovered) ? cs.primary : borderBase;
    final fg = widget.selected ? cs.primary : cs.onSurface.withOpacity(0.8);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
          ),
        ),
      ),
    );
  }
}
