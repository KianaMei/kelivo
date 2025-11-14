import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/tag_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';

Future<void> showAssistantTagsManagerDialog(
  BuildContext context, {
  required String assistantId,
}) async {
  final cs = Theme.of(context).colorScheme;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'tags-manager',
    barrierColor: Colors.black.withOpacity(0.15),
    pageBuilder: (ctx, _, __) {
      final l10n = AppLocalizations.of(ctx)!;
      // 使用全屏点击区域，允许点击对话框外侧关闭
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).maybePop(),
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {},
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 520, maxHeight: 600),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color:
                            Theme.of(ctx).brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.08)
                                : cs.outlineVariant.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: _TagsManagerBody(
                    assistantId: assistantId,
                    isDialog: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale:
              Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _TagsManagerBody extends StatefulWidget {
  const _TagsManagerBody({
    required this.assistantId,
    required this.isDialog,
  });

  final String assistantId;
  final bool isDialog;

  @override
  State<_TagsManagerBody> createState() => _TagsManagerBodyState();
}

class _TagsManagerBodyState extends State<_TagsManagerBody> {
  String _t(BuildContext context, String zh, String en) {
    final locale = AppLocalizations.of(context)!.localeName;
    return locale.startsWith('zh') ? zh : en;
  }

  Future<void> _createTag(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, '创建标签', 'Create Tag')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _t(context, '标签名称', 'Tag name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t(context, '创建', 'Create')),
          ),
        ],
      ),
    );
    if (ok == true) {
      final name = c.text.trim();
      if (name.isEmpty) return;
      final tp = context.read<TagProvider>();
      if (tp.tags.any((t) => t.name == name)) return;
      await tp.createTag(name);
    }
  }

  Future<void> _renameTag(
    BuildContext context,
    String tagId,
    String oldName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController c = TextEditingController(text: oldName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, '重命名标签', 'Rename Tag')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _t(context, '标签名称', 'Tag name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t(context, '重命名', 'Rename')),
          ),
        ],
      ),
    );
    if (ok == true) {
      final name = c.text.trim();
      if (name.isEmpty) return;
      final tp = context.read<TagProvider>();
      if (tp.tags.any((t) => t.name == name && t.id != tagId)) return;
      await tp.renameTag(tagId, name);
    }
  }

  Future<void> _deleteTag(BuildContext context, String tagId) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, '删除标签', 'Delete Tag')),
        content: Text(
          _t(
            context,
            '确定要删除该标签吗？',
            'Are you sure you want to delete this tag?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<TagProvider>().deleteTag(tagId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tp = context.watch<TagProvider>();
    final tags = tp.tags;
    final body = ReorderableListView.builder(
      itemCount: tags.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return ScaleTransition(
          scale:
              Tween<double>(begin: 1.0, end: 1.02).animate(animation),
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex -= 1;
        await context
            .read<TagProvider>()
            .reorderTags(oldIndex, newIndex);
      },
      itemBuilder: (ctx, i) {
        final t = tags[i];
        return KeyedSubtree(
          key: ValueKey('tag-desktop-${t.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: ReorderableDelayedDragStartListener(
              index: i,
              child: _DesktopTagCard(
                title: t.name,
                onTap: () async {
                  await context
                      .read<TagProvider>()
                      .assignAssistantToTag(widget.assistantId, t.id);
                  if (widget.isDialog && mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
                onRename: () =>
                    _renameTag(context, t.id, t.name),
                onDelete: () => _deleteTag(context, t.id),
              ),
            ),
          ),
        );
      },
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(context, '管理标签', 'Manage Tags'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Lucide.Plus, size: 20),
                onPressed: () => _createTag(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _DesktopTagCard extends StatefulWidget {
  const _DesktopTagCard({
    required this.title,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_DesktopTagCard> createState() => _DesktopTagCardState();
}

class _DesktopTagCardState extends State<_DesktopTagCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : const Color(0xFFF7F7F9);
    final borderColor =
        cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.10);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hover ? baseBg.withOpacity(0.95) : baseBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallIconBtn(
                icon: Lucide.Pencil,
                onTap: widget.onRename,
              ),
              const SizedBox(width: 6),
              _SmallIconBtn(
                icon: Lucide.Trash2,
                onTap: widget.onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  const _SmallIconBtn({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
