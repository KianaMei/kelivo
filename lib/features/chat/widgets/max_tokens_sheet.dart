import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';

Future<void> showMaxTokensSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _MaxTokensSheet(),
  );
}

class _MaxTokensSheet extends StatefulWidget {
  const _MaxTokensSheet();
  @override
  State<_MaxTokensSheet> createState() => _MaxTokensSheetState();
}

class _MaxTokensSheetState extends State<_MaxTokensSheet> {
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

    // Determine max limit based on API type
    if (kind == ProviderKind.claude) {
      return 64000;
    } else if (kind == ProviderKind.google) {
      return 65535;
    } else {
      // OpenAI and others default to 128000
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
    if (value == 0) {
      return AppLocalizations.of(context)!.maxTokensSheetUnlimited;
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
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    final maxLimit = _getMaxLimit();

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
                      Icon(Lucide.FileText, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.maxTokensSheetTitle,
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
                        l10n.maxTokensSheetCurrentValue,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        _formatValue(_value),
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
                      min: 0,
                      max: maxLimit.toDouble(),
                      divisions: maxLimit ~/ 1000, // 每1000一个刻度
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
                        l10n.maxTokensSheetUnlimited,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        _formatValue(maxLimit),
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
                    l10n.maxTokensSheetDescription(_formatValue(maxLimit)),
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
                        label: l10n.maxTokensSheetUnlimited,
                        value: 0,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(0);
                        },
                      ),
                      _PresetChip(
                        label: '4K',
                        value: 4000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(4000);
                        },
                      ),
                      _PresetChip(
                        label: '8K',
                        value: 8000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(8000);
                        },
                      ),
                      _PresetChip(
                        label: '16K',
                        value: 16000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(16000);
                        },
                      ),
                      _PresetChip(
                        label: '32K',
                        value: 32000,
                        currentValue: _value,
                        onTap: () {
                          Haptics.light();
                          _updateValue(32000);
                        },
                      ),
                      if (maxLimit >= 64000)
                        _PresetChip(
                          label: '64K',
                          value: 64000,
                          currentValue: _value,
                          onTap: () {
                            Haptics.light();
                            _updateValue(64000);
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
