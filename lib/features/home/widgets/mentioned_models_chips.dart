import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../utils/brand_assets.dart';
import '../../model/widgets/model_select_sheet.dart';

/// A horizontal scrollable row of chips displaying mentioned models.
/// Each chip shows the model name, provider name, and brand icon with a remove button.
class MentionedModelsChips extends StatelessWidget {
  const MentionedModelsChips({
    super.key,
    required this.mentionedModels,
    required this.onRemove,
    this.providerNames = const {},
    this.modelDisplayNames = const {},
  });

  /// List of mentioned models to display as chips
  final List<ModelSelection> mentionedModels;

  /// Callback when a model chip's remove button is tapped
  final ValueChanged<ModelSelection> onRemove;

  /// Map of providerKey -> display name for showing provider names
  final Map<String, String> providerNames;

  /// Map of "providerKey::modelId" -> display name for showing model names
  final Map<String, String> modelDisplayNames;

  @override
  Widget build(BuildContext context) {
    if (mentionedModels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: mentionedModels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final model = mentionedModels[index];
          return _ModelChip(
            model: model,
            providerName: providerNames[model.providerKey] ?? model.providerKey,
            modelDisplayName: modelDisplayNames['${model.providerKey}::${model.modelId}'] ?? model.modelId,
            onRemove: () => onRemove(model),
          );
        },
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.model,
    required this.providerName,
    required this.modelDisplayName,
    required this.onRemove,
  });

  final ModelSelection model;
  final String providerName;
  final String modelDisplayName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    // Get brand icon for the model
    final assetPath = BrandAssets.assetForName(model.modelId) ?? 
                      BrandAssets.assetForName(providerName);

    return Container(
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: isDark 
            ? cs.surfaceContainerHighest.withOpacity(0.6)
            : cs.surfaceContainerHighest.withOpacity(0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.1)
              : cs.outline.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Brand icon
          if (assetPath != null) ...[
            _buildIcon(assetPath),
            const SizedBox(width: 6),
          ],
          // Model name and provider
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelDisplayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  providerName,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withOpacity(0.6),
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Remove button
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Lucide.X,
                size: 12,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(String assetPath) {
    if (assetPath.endsWith('.svg')) {
      return SvgPicture.asset(
        assetPath,
        width: 18,
        height: 18,
      );
    } else {
      return Image.asset(
        assetPath,
        width: 18,
        height: 18,
        errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
      );
    }
  }
}
