import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/agent.dart';
import '../../core/models/agent_session.dart';
import '../../core/providers/agent_provider.dart'
    if (dart.library.html) '../../core/providers/agent_provider_stub.dart';
import '../../icons/lucide_adapter.dart' as lucide;

/// Agent sidebar showing agents and sessions
class AgentSidebar extends StatelessWidget {
  const AgentSidebar({
    super.key,
    this.width = 260,
    this.onNewAgent,
    this.onNewSession,
    this.onAgentSettings,
  });

  final double width;
  final VoidCallback? onNewAgent;
  final VoidCallback? onNewSession;
  final void Function(Agent agent)? onAgentSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AgentProvider>();

    return Material(
      color: cs.surfaceContainerLowest,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: cs.outline.withOpacity(0.15))),
        ),
        child: Column(
        children: [
          // Header with new agent button
          _SidebarHeader(onNewAgent: onNewAgent),
          const Divider(height: 1),

          // Agent selector dropdown
          _AgentSelector(
            agents: provider.agents,
            currentAgent: provider.currentAgent,
            onSelect: (agent) => provider.setCurrentAgent(agent.id),
            onSettings: onAgentSettings,
          ),

          const Divider(height: 1),

          // Sessions list
          Expanded(
            child: _SessionsList(
              sessions: provider.sessions,
              currentSessionId: provider.currentSessionId,
              onSelect: (session) => provider.setCurrentSession(session.id),
              onNewSession: onNewSession,
              onDelete: (session) => provider.deleteSession(session.id),
              onRename: (session, name) => provider.renameSession(session.id, name),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({this.onNewAgent});
  final VoidCallback? onNewAgent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(lucide.Lucide.Bot, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'Agent',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(lucide.Lucide.Plus, size: 18),
            tooltip: 'New Agent',
            onPressed: onNewAgent,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AgentSelector extends StatelessWidget {
  const _AgentSelector({
    required this.agents,
    this.currentAgent,
    this.onSelect,
    this.onSettings,
  });

  final List<Agent> agents;
  final Agent? currentAgent;
  final void Function(Agent)? onSelect;
  final void Function(Agent)? onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (agents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '暂无智能体',
          style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: MenuAnchor(
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44, // Fixed height for consistency
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow, // Lighter background
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outline.withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        _AgentAvatar(
                          name: currentAgent?.name ?? '?',
                          size: 28,
                          color: cs.primary, // Use primary color for avatar
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentAgent?.name ?? '选择智能体', // Only name, no description
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          lucide.Lucide.ChevronDown,
                          size: 16,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                );
              },
              menuChildren: agents.map((agent) {
                final isSelected = agent.id == currentAgent?.id;
                
                // Determine style for selected vs unselected
                final bgColor = isSelected 
                    ? cs.primaryContainer.withOpacity(0.5) // Light purple/pinkish
                    : null; // Transparent by default
                
                final textColor = isSelected ? cs.primary : cs.onSurface;
                final fontWeight = isSelected ? FontWeight.w600 : FontWeight.w500;

                return MenuItemButton(
                  onPressed: () => onSelect?.call(agent),
                  style: ButtonStyle(
                    padding: MaterialStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    backgroundColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.hovered)) {
                        return cs.surfaceContainerHighest.withOpacity(0.5);
                      }
                      return bgColor;
                    }),
                    shape: MaterialStateProperty.all(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Rounded items
                    ),
                    overlayColor: MaterialStateProperty.all(Colors.transparent), // cleaner hover
                  ),
                  child: Container( // Wrap content to ensure full width hit test and layout
                    constraints: const BoxConstraints(minWidth: 180),
                    child: Row(
                      children: [
                        _AgentAvatar(
                          name: agent.name,
                          size: 28, // Slightly larger avatar in list
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                          backgroundColor: isSelected ? Colors.white.withOpacity(0.5) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            agent.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: fontWeight,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected)
                          Icon(lucide.Lucide.Check, size: 16, color: cs.primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
              style: MenuStyle(
                backgroundColor: MaterialStateProperty.all(cs.surface),
                elevation: MaterialStateProperty.all(6),
                shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.2)),
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outline.withOpacity(0.05)),
                  ),
                ),
                padding: MaterialStateProperty.all(const EdgeInsets.all(8)),
                maximumSize: MaterialStateProperty.all(const Size(320, 500)),
              ),
            ),
          ),
          if (currentAgent != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(lucide.Lucide.Settings2, size: 18),
              tooltip: '智能体设置',
              onPressed: () => onSettings?.call(currentAgent!),
              style: IconButton.styleFrom(
                // Cleaner icon button style
                foregroundColor: cs.onSurface.withOpacity(0.7),
                hoverColor: cs.surfaceContainerHighest,
                padding: const EdgeInsets.all(8),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({
    required this.name,
    required this.size,
    required this.color,
    this.backgroundColor,
  });

  final String name;
  final double size;
  final Color color;
  final Color? backgroundColor;

  String get _initials {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length > 1) {
      if (RegExp(r'^[a-zA-Z]').hasMatch(parts[0])) {
         return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
    }
    if (name.isNotEmpty) {
      return name.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _SessionsList extends StatelessWidget {
  const _SessionsList({
    required this.sessions,
    this.currentSessionId,
    this.onSelect,
    this.onNewSession,
    this.onDelete,
    this.onRename,
  });

  final List<AgentSession> sessions;
  final String? currentSessionId;
  final void Function(AgentSession)? onSelect;
  final VoidCallback? onNewSession;
  final void Function(AgentSession)? onDelete;
  final void Function(AgentSession, String)? onRename;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // New session button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: InkWell(
            onTap: onNewSession,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(lucide.Lucide.Plus, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '新会话',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Sessions list
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    '暂无会话',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isSelected = session.id == currentSessionId;
                    return _SessionTile(
                      session: session,
                      isSelected: isSelected,
                      onTap: () => onSelect?.call(session),
                      onDelete: () => onDelete?.call(session),
                      onRename: (name) => onRename?.call(session, name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatefulWidget {
  const _SessionTile({
    required this.session,
    required this.isSelected,
    this.onTap,
    this.onDelete,
    this.onRename,
  });

  final AgentSession session;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final void Function(String)? onRename;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hovering = false;
  bool _editing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.session.name);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _editController.text = widget.session.name;
    });
  }

  void _finishEditing() {
    final newName = _editController.text.trim();
    if (newName.isNotEmpty && newName != widget.session.name) {
      widget.onRename?.call(newName);
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: _startEditing,
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? cs.primary.withOpacity(0.12)
                : _hovering
                    ? cs.surfaceContainerHighest
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _getStatusIcon(widget.session.status),
                size: 14,
                color: _getStatusColor(widget.session.status, cs),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _editController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _finishEditing(),
                        onEditingComplete: _finishEditing,
                      )
                    : Text(
                        widget.session.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (_hovering && !_editing)
                Material(
                  type: MaterialType.transparency,
                  child: IconButton(
                    icon: Icon(lucide.Lucide.Trash2, size: 14),
                    onPressed: widget.onDelete,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: '删除会话',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final cs = Theme.of(context).colorScheme;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(lucide.Lucide.Pencil, size: 16, color: cs.onSurface),
              const SizedBox(width: 8),
              const Text('重命名'),
            ],
          ),
          onTap: _startEditing,
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(lucide.Lucide.Trash2, size: 16, color: cs.error),
              const SizedBox(width: 8),
              Text('删除', style: TextStyle(color: cs.error)),
            ],
          ),
          onTap: widget.onDelete,
        ),
      ],
    );
  }

  IconData _getStatusIcon(AgentSessionStatus status) {
    switch (status) {
      case AgentSessionStatus.idle:
        return lucide.Lucide.Circle;
      case AgentSessionStatus.running:
        return lucide.Lucide.Loader;
      case AgentSessionStatus.waitingPermission:
        return lucide.Lucide.ShieldQuestion;
      case AgentSessionStatus.completed:
        return lucide.Lucide.CheckCircle;
      case AgentSessionStatus.aborted:
        return lucide.Lucide.StopCircle;
      case AgentSessionStatus.error:
        return lucide.Lucide.AlertCircle;
    }
  }

  Color _getStatusColor(AgentSessionStatus status, ColorScheme cs) {
    switch (status) {
      case AgentSessionStatus.idle:
        return cs.onSurface.withOpacity(0.4);
      case AgentSessionStatus.running:
        return cs.primary;
      case AgentSessionStatus.waitingPermission:
        return Colors.orange;
      case AgentSessionStatus.completed:
        return Colors.green;
      case AgentSessionStatus.aborted:
        return cs.outline;
      case AgentSessionStatus.error:
        return cs.error;
    }
  }
}
