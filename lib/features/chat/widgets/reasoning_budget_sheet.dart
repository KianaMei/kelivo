import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/helpers/chat_api_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptics.dart';

/// Effort levels: auto, off, minimal, low, medium, high
const List<int> _effortLevels = [
  ChatApiHelper.effortAuto,    // -1
  ChatApiHelper.effortOff,     // 0
  ChatApiHelper.effortMinimal, // -10
  ChatApiHelper.effortLow,     // -20
  ChatApiHelper.effortMedium,  // -30
  ChatApiHelper.effortHigh,    // -40
];

Future<void> showReasoningBudgetSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ReasoningEffortSheet(),
  );
}

class _ReasoningEffortSheet extends StatefulWidget {
  const _ReasoningEffortSheet();
  @override
  State<_ReasoningEffortSheet> createState() => _ReasoningEffortSheetState();
}

class _ReasoningEffortSheetState extends State<_ReasoningEffortSheet> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selectedIndex = _valueToIndex(s.thinkingBudget ?? ChatApiHelper.effortAuto);
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
    Haptics.light();
    setState(() => _selectedIndex = index);
    context.read<SettingsProvider>().setThinkingBudget(_effortLevels[index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.reasoningBudgetSliderTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Effort level selector
            _EffortLevelSelector(
              selectedIndex: _selectedIndex,
              onSelect: _onSelect,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Beautiful effort level selector for mobile
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
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final isSelected = i == selectedIndex;
          final color = _colorForIndex(i);

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.only(left: i > 0 ? 3 : 0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(isDark ? 0.85 : 0.9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 12,
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
