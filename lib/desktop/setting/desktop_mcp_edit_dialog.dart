import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../core/providers/mcp_provider.dart';
import '../../shared/widgets/snackbar.dart';
import '../../shared/widgets/ios_switch.dart';

Future<void> showDesktopMcpEditDialog(BuildContext context, {String? serverId}) async {
  final cs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: _DesktopMcpEditDialog(serverId: serverId),
      ),
    ),
  );
}

class _DesktopMcpEditDialog extends StatefulWidget {
  const _DesktopMcpEditDialog({this.serverId});
  final String? serverId;

  @override
  State<_DesktopMcpEditDialog> createState() => _DesktopMcpEditDialogState();
}

class _DesktopMcpEditDialogState extends State<_DesktopMcpEditDialog> {
  bool get isEdit => widget.serverId != null;

  bool _enabled = true;
  final _nameCtrl = TextEditingController();
  McpTransportType _transport = McpTransportType.http;
  final _urlCtrl = TextEditingController();
  final List<_HeaderEntry> _headers = [];

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final server = context.read<McpProvider>().getById(widget.serverId!)!;
      _enabled = server.enabled;
      _nameCtrl.text = server.name;
      _transport = server.transport;
      _urlCtrl.text = server.url;
      server.headers.forEach((k, v) {
        _headers.add(_HeaderEntry(TextEditingController(text: k), TextEditingController(text: v)));
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    for (final h in _headers) { h.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.read<McpProvider>();

    // Inmemory server: only allow toggling enabled
    if (isEdit && _transport == McpTransportType.inmemory) {
      final old = mcp.getById(widget.serverId!)!;
      await mcp.updateServer(old.copyWith(enabled: _enabled));
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    final name = _nameCtrl.text.trim().isEmpty ? 'MCP' : _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final headers = <String, String>{
      for (final h in _headers)
        if (h.key.text.trim().isNotEmpty) h.key.text.trim(): h.value.text.trim()
    };

    if (url.isEmpty) {
      showAppSnackBar(context, message: l10n.mcpServerEditSheetUrlRequired, type: NotificationType.warning);
      return;
    }

    if (isEdit) {
      final old = mcp.getById(widget.serverId!)!;
      await mcp.updateServer(old.copyWith(
        enabled: _enabled,
        name: name,
        transport: _transport,
        url: url,
        headers: headers,
      ));
    } else {
      await mcp.addServer(
        enabled: _enabled,
        name: name,
        transport: _transport,
        url: url,
        headers: headers,
      );
    }

    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final isInmemory = isEdit && _transport == McpTransportType.inmemory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        _buildHeader(),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),

        // Form
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Enabled toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.mcpServerEditSheetEnabledLabel,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IosSwitch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              if (isInmemory) ...[
                // Inmemory: show name as read-only
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        l10n.mcpServerEditSheetNameLabel,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _nameCtrl.text,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Name field
                _labeledField(
                  label: l10n.mcpServerEditSheetNameLabel,
                  controller: _nameCtrl,
                  hint: 'My MCP',
                  bold: true,
                ),
                const SizedBox(height: 10),

                // Transport type selector
                Text(
                  l10n.mcpServerEditSheetTransportLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                _SegChoiceBar(
                  labels: const ['Streamable HTTP', 'SSE'],
                  selectedIndex: _transport == McpTransportType.http ? 0 : 1,
                  onSelected: (i) {
                    setState(() {
                      _transport = i == 0 ? McpTransportType.http : McpTransportType.sse;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // SSE retry hint
                if (_transport == McpTransportType.sse)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l10n.mcpServerEditSheetSseRetryHint,
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                    ),
                  ),

                // URL field
                _labeledField(
                  label: l10n.mcpServerEditSheetUrlLabel,
                  controller: _urlCtrl,
                  hint: _transport == McpTransportType.sse
                      ? 'http://localhost:3000/sse'
                      : 'http://localhost:3000',
                  bold: true,
                ),
                const SizedBox(height: 16),

                // Headers section
                Text(
                  l10n.mcpServerEditSheetCustomHeadersTitle,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...List.generate(_headers.length, (i) {
                  final h = _headers[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _labeledField(
                            label: l10n.mcpServerEditSheetHeaderNameLabel,
                            controller: h.key,
                            hint: l10n.mcpServerEditSheetHeaderNameHint,
                            bold: false,
                          ),
                          const SizedBox(height: 10),
                          _labeledField(
                            label: l10n.mcpServerEditSheetHeaderValueLabel,
                            controller: h.value,
                            hint: l10n.mcpServerEditSheetHeaderValueHint,
                            bold: false,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _SmallIconBtn(
                              icon: Lucide.Trash2,
                              tooltip: l10n.mcpServerEditSheetRemoveHeaderTooltip,
                              onTap: () {
                                setState(() {
                                  _headers[i].dispose();
                                  _headers.removeAt(i);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Lucide.Plus, size: 16),
                    label: Text(l10n.mcpServerEditSheetAddHeader),
                    onPressed: () {
                      setState(() {
                        _headers.add(_HeaderEntry(TextEditingController(), TextEditingController()));
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        // Footer
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.mcpServerEditSheetCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.mcpServerEditSheetSave),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isEdit ? l10n.mcpServerEditSheetTitleEdit : l10n.mcpServerEditSheetTitleAdd,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (isEdit)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _SmallIconBtn(
                  icon: Lucide.RefreshCw,
                  tooltip: l10n.mcpServerEditSheetSyncToolsTooltip,
                  onTap: () async {
                    await context.read<McpProvider>().refreshTools(widget.serverId!);
                  },
                ),
              ),
            _SmallIconBtn(
              icon: Lucide.X,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required bool bold,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08)),
      ),
      child: child,
    );
  }
}

class _HeaderEntry {
  final TextEditingController key;
  final TextEditingController value;

  _HeaderEntry(this.key, this.value);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _SmallIconBtn extends StatefulWidget {
  const _SmallIconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
        : Colors.transparent;
    final btn = MouseRegion(
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
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

// Segmented choice bar (like iOS UISegmentedControl)
class _SegChoiceBar extends StatelessWidget {
  const _SegChoiceBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double outerHeight = 44;
    const double innerPadding = 4;
    const double gap = 6;
    const double minSegWidth = 88;
    final double pillRadius = 18;
    final double innerRadius = ((pillRadius - innerPadding).clamp(0.0, pillRadius)).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double innerAvailWidth = availWidth - innerPadding * 2;
        final double segWidth = math.max(
          minSegWidth,
          (innerAvailWidth - gap * (labels.length - 1)) / labels.length,
        );

        final Color shellBg = isDark ? Colors.white.withOpacity(0.08) : Colors.white;

        List<Widget> children = [];
        for (int index = 0; index < labels.length; index++) {
          final bool selected = selectedIndex == index;
          children.add(
            SizedBox(
              width: segWidth,
              height: double.infinity,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: selected ? cs.primary.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(innerRadius),
                    ),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? cs.primary : cs.onSurface.withOpacity(0.82),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          if (index != labels.length - 1) children.add(const SizedBox(width: gap));
        }

        return Container(
          height: outerHeight,
          decoration: BoxDecoration(
            color: shellBg,
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.all(innerPadding),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(children: children),
            ),
          ),
        );
      },
    );
  }
}
