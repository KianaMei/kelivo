import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../core/providers/assistant_provider.dart';
import 'desktop_popover.dart';

/// Show desktop tool loop configuration popover with slider
Future<void> showDesktopToolLoopPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
}) async {
  await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: const _ToolLoopContent(),
    maxHeight: 420,
  );
}

class _ToolLoopContent extends StatefulWidget {
  const _ToolLoopContent();

  @override
  State<_ToolLoopContent> createState() => _ToolLoopContentState();
}

class _ToolLoopContentState extends State<_ToolLoopContent> {
  late int _value;

  @override
  void initState() {
    super.initState();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    _value = assistant?.maxToolLoopIterations ?? 10;
  }

  void _updateValue(int newValue) {
    setState(() => _value = newValue);
    final assistant = context.read<AssistantProvider>().currentAssistant;
    if (assistant != null) {
      context.read<AssistantProvider>().updateAssistant(
        assistant.copyWith(maxToolLoopIterations: newValue),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const maxLimit = 50;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Lucide.RefreshCw, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '工具循环次数',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              Text(
                _value.toString(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.primary.withOpacity(0.2),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withOpacity(0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _value.toDouble(),
              min: 1,
              max: maxLimit.toDouble(),
              divisions: maxLimit - 1,
              onChanged: (v) => _updateValue(v.round()),
            ),
          ),

          // Range labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '1',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  maxLimit.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Quick presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PresetChip(label: '5', value: 5, currentValue: _value, onTap: () => _updateValue(5)),
              _PresetChip(label: '10', value: 10, currentValue: _value, onTap: () => _updateValue(10)),
              _PresetChip(label: '15', value: 15, currentValue: _value, onTap: () => _updateValue(15)),
              _PresetChip(label: '20', value: 20, currentValue: _value, onTap: () => _updateValue(20)),
              _PresetChip(label: '30', value: 30, currentValue: _value, onTap: () => _updateValue(30)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatefulWidget {
  const _PresetChip({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.onTap,
  });

  final String label;
  final int value;
  final int currentValue;
  final VoidCallback onTap;

  @override
  State<_PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<_PresetChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = widget.currentValue == widget.value;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withOpacity(0.15)
                : (_hovered
                    ? (isDark ? Colors.white : Colors.black).withOpacity(isDark ? 0.08 : 0.05)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? cs.primary.withOpacity(0.4) : cs.onSurface.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.8),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

