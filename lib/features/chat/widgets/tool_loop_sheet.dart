import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';

Future<void> showToolLoopSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ToolLoopSheet(),
  );
}

class _ToolLoopSheet extends StatefulWidget {
  const _ToolLoopSheet();
  @override
  State<_ToolLoopSheet> createState() => _ToolLoopSheetState();
}

class _ToolLoopSheetState extends State<_ToolLoopSheet> {
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
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    const maxLimit = 50;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Lucide.RefreshCw, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '工具循环次数',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Current value display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '当前值',
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        _value.toString(),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.primary.withOpacity(0.2),
                      thumbColor: cs.primary,
                      overlayColor: cs.primary.withOpacity(0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _value.toDouble(),
                      min: 1,
                      max: maxLimit.toDouble(),
                      divisions: maxLimit - 1,
                      onChanged: (v) {
                        Haptics.light();
                        _updateValue(v.round());
                      },
                    ),
                  ),
                ),

                // Range labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        maxLimit.toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '设置工具调用的最大循环次数，防止无限循环。推荐值：5-20。过小可能导致复杂任务无法完成，过大可能消耗过多 tokens。',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.6),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Quick presets
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PresetChip(
                        label: '5',
                        value: 5,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(5);
                        },
                      ),
                      _PresetChip(
                        label: '10',
                        value: 10,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(10);
                        },
                      ),
                      _PresetChip(
                        label: '15',
                        value: 15,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(15);
                        },
                      ),
                      _PresetChip(
                        label: '20',
                        value: 20,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(20);
                        },
                      ),
                      _PresetChip(
                        label: '30',
                        value: 30,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(30);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = currentValue == value;

    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      baseColor: isSelected ? cs.primary.withOpacity(0.12) : cs.surface,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}

