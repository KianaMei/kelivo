import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../core/providers/settings_provider.dart';
import '../l10n/app_localizations.dart';
import 'desktop_popover.dart';

/// Show desktop reasoning budget selection popover
Future<void> showDesktopReasoningBudgetPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
}) async {
  await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: const _ReasoningBudgetContent(),
    maxHeight: 320,
  );
}

class _ReasoningBudgetContent extends StatefulWidget {
  const _ReasoningBudgetContent();

  @override
  State<_ReasoningBudgetContent> createState() =>
      _ReasoningBudgetContentState();
}

class _ReasoningBudgetContentState extends State<_ReasoningBudgetContent> {
  late int? _selected;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selected = s.thinkingBudget ?? -1;
  }

  int _bucket(int? n) {
    if (n == null) return -1;
    if (n == -1) return -1;
    if (n < 1024) return 0;
    if (n < 16000) return 1024;
    if (n < 32000) return 16000;
    return 32000;
  }

  void _select(int value) {
    setState(() => _selected = value);
    context.read<SettingsProvider>().setThinkingBudget(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final options = [
      (value: 0, icon: Lucide.X, label: l10n.reasoningBudgetSheetOff, deepthink: false),
      (value: -1, icon: Lucide.Settings2, label: l10n.reasoningBudgetSheetAuto, deepthink: false),
      (value: 1024, icon: Lucide.Brain, label: l10n.reasoningBudgetSheetLight, deepthink: true),
      (value: 16000, icon: Lucide.Brain, label: l10n.reasoningBudgetSheetMedium, deepthink: true),
      (value: 32000, icon: Lucide.Brain, label: l10n.reasoningBudgetSheetHeavy, deepthink: true),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: PopoverRowItem(
                  leading: opt.deepthink
                      ? SvgPicture.asset(
                          'assets/icons/deepthink.svg',
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(
                            _bucket(_selected) == opt.value
                                ? cs.primary
                                : cs.onSurface,
                            BlendMode.srcIn,
                          ),
                        )
                      : Icon(
                          opt.icon,
                          size: 16,
                          color: _bucket(_selected) == opt.value
                              ? cs.primary
                              : cs.onSurface,
                        ),
                  label: opt.label,
                  selected: _bucket(_selected) == opt.value,
                  onTap: () => _select(opt.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
