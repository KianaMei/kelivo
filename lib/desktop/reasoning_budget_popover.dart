import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import 'desktop_popover.dart';

/// Show desktop reasoning budget selection popover
Future<void> showDesktopReasoningBudgetPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required int? initialValue,
  required ValueChanged<int> onValueChanged,
}) async {
  // Obtain a programmatic close callback from the generic popover helper
  // and wire it into the content so that selecting an option
  // automatically dismisses the popover (matches remote behaviour).
  VoidCallback close = () {};
  close = await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _ReasoningBudgetContent(
      initialValue: initialValue,
      onValueChanged: onValueChanged,
      onDone: () => close(),
    ),
    maxHeight: 320,
  );
}

class _ReasoningBudgetContent extends StatefulWidget {
  const _ReasoningBudgetContent({
    required this.initialValue,
    required this.onValueChanged,
    required this.onDone,
  });

  final int? initialValue;
  final ValueChanged<int> onValueChanged;
  final VoidCallback onDone;

  @override
  State<_ReasoningBudgetContent> createState() =>
      _ReasoningBudgetContentState();
}

class _ReasoningBudgetContentState extends State<_ReasoningBudgetContent> {
  late int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue ?? -1;
    print('🔍 [ReasoningBudget] initState: initialValue = ${widget.initialValue}, _selected = $_selected');
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
    print('🎯 [ReasoningBudget] Selecting value: $value');
    setState(() => _selected = value);
    widget.onValueChanged(value);
    print('✅ [ReasoningBudget] Called onValueChanged with value: $value');
    widget.onDone();
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
