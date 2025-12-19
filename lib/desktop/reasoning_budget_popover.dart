import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/services/api/helpers/chat_api_helper.dart';
import 'desktop_popover.dart';

/// Effort levels: auto, off, minimal, low, medium, high
const List<int> _effortLevels = [
  ChatApiHelper.effortAuto,    // -1
  ChatApiHelper.effortOff,     // 0
  ChatApiHelper.effortMinimal, // -10
  ChatApiHelper.effortLow,     // -20
  ChatApiHelper.effortMedium,  // -30
  ChatApiHelper.effortHigh,    // -40
];

/// Show desktop reasoning effort selection popover
Future<void> showDesktopReasoningBudgetPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required int? initialValue,
  required ValueChanged<int> onValueChanged,
}) async {
  VoidCallback close = () {};
  close = await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _ReasoningEffortContent(
      initialValue: initialValue,
      onValueChanged: (v) {
        onValueChanged(v);
        close();
      },
    ),
    maxHeight: 100,
    minWidth: 380,
  );
}

class _ReasoningEffortContent extends StatefulWidget {
  const _ReasoningEffortContent({
    required this.initialValue,
    required this.onValueChanged,
  });

  final int? initialValue;
  final ValueChanged<int> onValueChanged;

  @override
  State<_ReasoningEffortContent> createState() => _ReasoningEffortContentState();
}

class _ReasoningEffortContentState extends State<_ReasoningEffortContent> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _valueToIndex(widget.initialValue ?? ChatApiHelper.effortAuto);
  }

  int _valueToIndex(int value) {
    for (int i = 0; i < _effortLevels.length; i++) {
      if (_effortLevels[i] == value) return i;
    }
    // For legacy positive values, map to closest effort
    if (value > 0) {
      if (value < 2048) return 2;       // minimal
      if (value < 8192) return 3;       // low
      if (value < 20000) return 4;      // medium
      return 5;                          // high
    }
    return 0; // auto
  }

  void _onSelect(int index) {
    setState(() => _selectedIndex = index);
    widget.onValueChanged(_effortLevels[index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reasoningBudgetSliderTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          _EffortLevelSelector(
            selectedIndex: _selectedIndex,
            onSelect: _onSelect,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

/// Beautiful effort level selector
class _EffortLevelSelector extends StatelessWidget {
  const _EffortLevelSelector({
    required this.selectedIndex,
    required this.onSelect,
    required this.isDark,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isDark;

  static const _labels = ['auto', 'off', 'minimal', 'low', 'medium', 'high'];
  static const _icons = [
    Icons.auto_awesome_outlined,  // auto
    Icons.block_outlined,         // off
    Icons.remove_outlined,        // minimal
    Icons.keyboard_arrow_down,    // low
    Icons.remove,                 // medium
    Icons.keyboard_arrow_up,      // high
  ];

  Color _colorForIndex(int i) {
    switch (i) {
      case 0: return Colors.blue;
      case 1: return Colors.grey;
      case 2: return Colors.teal;
      case 3: return Colors.green;
      case 4: return Colors.orange;
      case 5: return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final isSelected = i == selectedIndex;
          final color = _colorForIndex(i);

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(isDark ? 0.85 : 0.9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
