import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/assistant_provider.dart';
import 'desktop_popover.dart';

/// Show desktop max tokens selection popover with slider
Future<void> showDesktopMaxTokensPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
}) async {
  await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: const _MaxTokensContent(),
    maxHeight: 480,
  );
}

class _MaxTokensContent extends StatefulWidget {
  const _MaxTokensContent();

  @override
  State<_MaxTokensContent> createState() => _MaxTokensContentState();
}

class _MaxTokensContentState extends State<_MaxTokensContent> {
  late int _value;

  @override
  void initState() {
    super.initState();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    _value = assistant?.maxTokens ?? 0;
  }

  int _getMaxLimit() {
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) return 128000;

    final cfg = settings.getProviderConfig(providerKey);
    if (cfg == null) return 128000;

    final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);

    if (kind == ProviderKind.claude) {
      return 64000;
    } else if (kind == ProviderKind.google) {
      return 65535;
    } else {
      return 128000;
    }
  }

  void _updateValue(int newValue) {
    setState(() => _value = newValue);
    final assistant = context.read<AssistantProvider>().currentAssistant;
    if (assistant != null) {
      context.read<AssistantProvider>().updateAssistant(
        assistant.copyWith(maxTokens: newValue),
      );
    }
  }

  String _formatValue(int value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == 0) {
      return l10n.maxTokensSheetUnlimited;
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    } else {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxLimit = _getMaxLimit();

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
                child: Icon(Lucide.FileText, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.maxTokensSheetTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              Text(
                _formatValue(_value),
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
              min: 0,
              max: maxLimit.toDouble(),
              divisions: maxLimit ~/ 1000,
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
                  l10n.maxTokensSheetUnlimited,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _formatValue(maxLimit),
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
              _PresetChip(
                label: l10n.maxTokensSheetUnlimited,
                value: 0,
                currentValue: _value,
                onTap: () => _updateValue(0),
              ),
              _PresetChip(label: '4K', value: 4000, currentValue: _value, onTap: () => _updateValue(4000)),
              _PresetChip(label: '8K', value: 8000, currentValue: _value, onTap: () => _updateValue(8000)),
              _PresetChip(label: '16K', value: 16000, currentValue: _value, onTap: () => _updateValue(16000)),
              _PresetChip(label: '32K', value: 32000, currentValue: _value, onTap: () => _updateValue(32000)),
              if (maxLimit >= 64000)
                _PresetChip(label: '64K', value: 64000, currentValue: _value, onTap: () => _updateValue(64000)),
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
