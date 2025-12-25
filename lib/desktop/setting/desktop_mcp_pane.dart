import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../core/providers/mcp_provider.dart';
import '../../shared/widgets/snackbar.dart';
import 'desktop_mcp_edit_dialog.dart' show showDesktopMcpEditDialog;
import 'desktop_mcp_json_edit_dialog.dart' show showDesktopMcpJsonEditDialog;

class DesktopMcpPane extends StatelessWidget {
  const DesktopMcpPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final servers = mcp.servers;

    return Container(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.settingsPageMcp,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      _SmallIconBtn(
                        icon: Lucide.Edit,
                        onTap: () async {
                          await showDesktopMcpJsonEditDialog(context);
                        },
                      ),
                      const SizedBox(width: 6),
                      _SmallIconBtn(
                        icon: Lucide.Plus,
                        onTap: () async {
                          await showDesktopMcpEditDialog(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              if (servers.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    alignment: Alignment.center,
                    child: Text(
                      l10n.mcpPageNoServers,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final s = servers[index];
                      final status = mcp.statusFor(s.id);
                      final error = mcp.errorFor(s.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ServerCard(
                          server: s,
                          status: status,
                          error: error,
                          onTap: () async {
                            await showDesktopMcpEditDialog(context, serverId: s.id);
                          },
                          onReconnect: () async {
                            await context.read<McpProvider>().reconnect(s.id);
                          },
                          onDelete: () async {
                            final ok = await _confirmDelete(context);
                            if (ok == true) {
                              await context.read<McpProvider>().removeServer(s.id);
                              if (context.mounted) {
                                showAppSnackBar(context, message: l10n.mcpPageServerDeleted);
                              }
                            }
                          },
                          onDetails: () async {
                            await _showErrorDetails(context, name: s.name, message: error);
                          },
                        ),
                      );
                    },
                    childCount: servers.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({
    required this.server,
    required this.status,
    required this.error,
    required this.onTap,
    required this.onReconnect,
    required this.onDelete,
    required this.onDetails,
  });

  final McpServerConfig server;
  final McpStatus status;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onReconnect;
  final VoidCallback onDelete;
  final VoidCallback onDetails;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _hover = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final s = widget.server;

    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderColor = _hover
        ? cs.primary.withOpacity(isDark ? 0.35 : 0.45)
        : cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08);

    Color statusColor;
    String statusText;
    switch (widget.status) {
      case McpStatus.connected:
        statusColor = Colors.green;
        statusText = l10n.mcpPageStatusConnected;
        break;
      case McpStatus.connecting:
        statusColor = cs.primary;
        statusText = l10n.mcpPageStatusConnecting;
        break;
      case McpStatus.error:
      case McpStatus.idle:
      default:
        statusColor = Colors.redAccent;
        statusText = l10n.mcpPageStatusDisconnected;
        break;
    }

    Widget tag(String text, {Color? color}) {
      final c = color ?? cs.primary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withOpacity(0.35)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700),
        ),
      );
    }

    String transportText;
    switch (s.transport) {
      case McpTransportType.sse:
        transportText = 'SSE';
        break;
      case McpTransportType.http:
        transportText = 'HTTP';
        break;
      case McpTransportType.inmemory:
        transportText = l10n.mcpTransportTagInmemory;
        break;
    }

    final showError = widget.status == McpStatus.error && (widget.error?.isNotEmpty ?? false);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: baseBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        constraints: const BoxConstraints(minHeight: 64),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Lucide.Terminal, size: 18, color: cs.primary),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: widget.status == McpStatus.connecting
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                                  ),
                                )
                              : Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: s.enabled ? statusColor : cs.outline,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              tag(statusText, color: statusColor),
                              tag(transportText),
                              tag(l10n.mcpPageToolsCount(s.tools.where((t) => t.enabled).length, s.tools.length)),
                              if (!s.enabled)
                                tag(l10n.mcpPageStatusDisabled, color: cs.onSurface.withOpacity(0.7)),
                            ],
                          ),
                          if (showError) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Lucide.MessageCircleWarning, size: 14, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.mcpPageConnectionFailed,
                                    style: const TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.onDetails,
                                  style: ButtonStyle(
                                    splashFactory: NoSplash.splashFactory,
                                    overlayColor: const MaterialStatePropertyAll(Colors.transparent),
                                  ),
                                  child: Text(l10n.mcpPageDetails),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SmallIconBtn(icon: Lucide.Settings2, onTap: widget.onTap),
                    const SizedBox(width: 6),
                    _SmallIconBtn(icon: Lucide.RefreshCw, onTap: widget.onReconnect),
                    const SizedBox(width: 6),
                    _SmallIconBtn(icon: Lucide.Trash2, onTap: widget.onDelete),
                    const SizedBox(width: 8),
                    Icon(_expanded ? Lucide.ChevronUp : Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.5)),
                  ],
                ),
              ),
            ),
              if (_expanded)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.1))),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(context, 'URL', s.url),
                      if (s.headers.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildDetailRow(context, 'Headers', '${s.headers.length} custom headers'),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        l10n.mcpToolsTitle(s.tools.length),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7)),
                      ),
                      const SizedBox(height: 8),
                      if (s.tools.isEmpty)
                        Text(
                          l10n.mcpNoToolsAvailable,
                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.5), fontStyle: FontStyle.italic),
                        )
                      else
                        ...s.tools.map((t) => _buildToolItem(context, t)),
                    ],
                  ),
                ),
            ],
          ),
        ),

    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.8), fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildToolItem(BuildContext context, McpToolConfig t) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary),
                ),
              ),
              if (!t.enabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.mcpToolDisabled,
                    style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.6)),
                  ),
                ),
            ],
          ),
          if (t.description?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              t.description!,
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
            ),
          ],
          if (t.params.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.mcpInputParameters,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 4),
            ...t.params.map((p) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.8), fontFamily: 'monospace'),
                      ),
                      if (p.required)
                        Text('*', style: TextStyle(fontSize: 11, color: Colors.red)),
                      const SizedBox(width: 8),
                      Text(
                        p.type ?? 'any',
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _SmallIconBtn extends StatefulWidget {
  const _SmallIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent;
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

Future<void> _showErrorDetails(BuildContext context, {required String name, String? message}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.mcpPageErrorDialogTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(name, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    _SmallIconBtn(
                      icon: Lucide.X,
                      onTap: () => Navigator.of(ctx).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      (message?.isNotEmpty == true ? message! : l10n.mcpPageErrorNoDetails),
                      style: (Theme.of(ctx).textTheme.bodyMedium ?? const TextStyle())
                          .copyWith(fontSize: 13.0, height: 1.35),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).maybePop(),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(l10n.mcpPageClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool?> _confirmDelete(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.mcpPageConfirmDeleteTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(l10n.mcpPageConfirmDeleteContent, style: TextStyle(color: cs.onSurface.withOpacity(0.8))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Builder(builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: ButtonStyle(
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: const MaterialStatePropertyAll(Colors.transparent),
                          minimumSize: const MaterialStatePropertyAll(Size(88, 36)),
                          shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          backgroundColor: MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.hovered)) {
                              return isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
                            }
                            return Colors.transparent;
                          }),
                        ),
                        child: Text(l10n.mcpPageCancel),
                      );
                    }),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError)
                          .copyWith(
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: const MaterialStatePropertyAll(Colors.transparent),
                            minimumSize: const MaterialStatePropertyAll(Size(88, 36)),
                            shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            backgroundColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.hovered)) {
                                return Color.lerp(cs.error, Colors.white, 0.08);
                              }
                              return cs.error;
                            }),
                          ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(l10n.mcpPageDelete),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
