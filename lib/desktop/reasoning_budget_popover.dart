import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'desktop_popover.dart';

/// Slider stops: Auto(-1), OFF(0), then exponential scale
const List<int> _sliderStops = [-1, 0, 128, 512, 1024, 2048, 4096, 8192, 16384, 24576, 32768];

/// Show desktop reasoning budget selection popover with slider
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
    child: _ReasoningBudgetSliderContent(
      initialValue: initialValue,
      onValueChanged: onValueChanged,
    ),
    maxHeight: 120,
    minWidth: 480,
  );
}

class _ReasoningBudgetSliderContent extends StatefulWidget {
  const _ReasoningBudgetSliderContent({
    required this.initialValue,
    required this.onValueChanged,
  });

  final int? initialValue;
  final ValueChanged<int> onValueChanged;

  @override
  State<_ReasoningBudgetSliderContent> createState() => _ReasoningBudgetSliderContentState();
}

class _ReasoningBudgetSliderContentState extends State<_ReasoningBudgetSliderContent> {
  late int _currentValue;
  late TextEditingController _textController;
  late int _sliderIndex;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue ?? -1;
    _sliderIndex = _valueToIndex(_currentValue);
    _textController = TextEditingController(text: _displayText(_currentValue));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int _valueToIndex(int value) {
    // Find closest slider stop
    for (int i = 0; i < _sliderStops.length; i++) {
      if (_sliderStops[i] >= value) return i;
    }
    return _sliderStops.length - 1;
  }

  String _displayText(int value) {
    if (value == -1) return 'Auto';
    if (value == 0) return 'OFF';
    return value.toString();
  }

  String _sliderLabel(int index) {
    final v = _sliderStops[index];
    if (v == -1) return 'Auto';
    if (v == 0) return 'OFF';
    if (v >= 1024) return '${(v / 1024).round()}K';
    return v.toString();
  }

  void _onSliderChanged(double value) {
    final index = value.round();
    final newValue = _sliderStops[index];
    setState(() {
      _sliderIndex = index;
      _currentValue = newValue;
      _textController.text = _displayText(newValue);
    });
    widget.onValueChanged(newValue);
  }

  void _onTextSubmitted(String text) {
    final trimmed = text.trim().toLowerCase();
    int newValue;
    if (trimmed == 'auto' || trimmed == '-1') {
      newValue = -1;
    } else if (trimmed == 'off' || trimmed == '0') {
      newValue = 0;
    } else {
      newValue = int.tryParse(trimmed) ?? _currentValue;
      // Clamp to valid range
      if (newValue < 0) newValue = 0;
      if (newValue > 32768) newValue = 32768;
    }
    setState(() {
      _currentValue = newValue;
      _sliderIndex = _valueToIndex(newValue);
      _textController.text = _displayText(newValue);
    });
    widget.onValueChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + param name tag
          Row(
            children: [
              Text(
                l10n.reasoningBudgetSliderTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'thinkingBudget',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Slider + Labels + Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Slider and labels in same Expanded container
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Effort level indicator bar - padding matches slider track
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _EffortLevelBar(currentIndex: _sliderIndex, isDark: isDark),
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        activeTrackColor: cs.primary.withOpacity(0.3),
                        inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                        thumbColor: cs.primary,
                        overlayColor: cs.primary.withOpacity(0.1),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 3),
                        activeTickMarkColor: cs.primary.withOpacity(0.5),
                        inactiveTickMarkColor: isDark ? Colors.white24 : Colors.black26,
                      ),
                      child: Slider(
                        value: _sliderIndex.toDouble(),
                        min: 0,
                        max: (_sliderStops.length - 1).toDouble(),
                        divisions: _sliderStops.length - 1,
                        onChanged: _onSliderChanged,
                      ),
                    ),
                    // Labels row directly under slider, same width
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          for (int i = 0; i < _sliderStops.length; i++) ...[
                            if (i > 0) const Spacer(),
                            Text(
                              _sliderLabel(i),
                              style: TextStyle(
                                fontSize: 9,
                                color: cs.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Numeric input box
              SizedBox(
                width: 72,
                height: 32,
                child: TextField(
                  controller: _textController,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.primary),
                    ),
                  ),
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z]')),
                  ],
                  onSubmitted: _onTextSubmitted,
                  onEditingComplete: () => _onTextSubmitted(_textController.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Effort level indicator bar showing minimal/low/medium/high zones
class _EffortLevelBar extends StatelessWidget {
  const _EffortLevelBar({required this.currentIndex, required this.isDark});
  
  final int currentIndex;
  final bool isDark;
  
  // Slider stops: Auto(-1), OFF(0), 128, 512, 1K, 2K, 4K, 8K, 16K, 24K, 32K
  // Index:           0       1     2    3    4   5    6   7    8    9   10
  // Effort:       auto     off  min  low  low low  med med high high high
  
  String _effortForIndex(int i) {
    if (i == 0) return 'auto';
    if (i == 1) return 'off';
    if (i == 2) return 'minimal';
    if (i <= 5) return 'low';
    if (i <= 7) return 'medium';
    return 'high';
  }
  
  Color _colorForEffort(String e) {
    switch (e) {
      case 'auto': return Colors.blue;
      case 'off': return Colors.grey;
      case 'minimal': return Colors.teal;
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final currentEffort = _effortForIndex(currentIndex);
    final segments = <_Segment>[
      _Segment('auto', 5),    // 0~0.5 (width 0.5)
      _Segment('off', 10),    // 0.5~1.5 (width 1)
      _Segment('minimal', 10),// 1.5~2.5 (width 1)
      _Segment('low', 30),    // 2.5~5.5 (width 3)
      _Segment('medium', 20), // 5.5~7.5 (width 2)
      _Segment('high', 25),   // 7.5~10 (width 2.5)
    ];
    final total = segments.fold<int>(0, (sum, s) => sum + s.width);
    
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (int i = 0; i < segments.length; i++) ...[
            Expanded(
              flex: segments[i].width,
              child: Container(
                margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(4) : Radius.zero,
                    right: i == segments.length - 1 ? const Radius.circular(4) : Radius.zero,
                  ),
                  color: _colorForEffort(segments[i].name).withOpacity(
                    currentEffort == segments[i].name ? 0.7 : (isDark ? 0.15 : 0.12),
                  ),
                ),
                alignment: i == 0 
                    ? Alignment.centerLeft 
                    : (i == segments.length - 1 ? Alignment.centerRight : Alignment.center),
                padding: EdgeInsets.only(
                  left: i == 0 ? 4 : 0,
                  right: i == segments.length - 1 ? 4 : 0,
                ),
                child: Text(
                  segments[i].name,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: currentEffort == segments[i].name ? FontWeight.w600 : FontWeight.normal,
                    color: currentEffort == segments[i].name
                        ? (isDark ? Colors.white : Colors.white)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment {
  final String name;
  final int width;
  const _Segment(this.name, this.width);
}
