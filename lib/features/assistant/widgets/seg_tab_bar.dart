import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tactile_widgets.dart';

/// Segmented tab bar with iOS-style design.
class SegTabBar extends StatelessWidget implements PreferredSizeWidget {
  const SegTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });
  
  final TabController controller;
  final List<String> tabs;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double outerHeight = 44;
    const double innerPadding = 4;
    const double gap = 6;
    const double minSegWidth = 88;
    final double pillRadius = 18;
    final double innerRadius = ((pillRadius - innerPadding).clamp(0.0, pillRadius)).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double innerAvailWidth = availWidth - innerPadding * 2;
        final double segWidth = math.max(
          minSegWidth,
          (innerAvailWidth - gap * (tabs.length - 1)) / tabs.length,
        );
        final double rowWidth = segWidth * tabs.length + gap * (tabs.length - 1);

        final Color shellBg = isDark ? Colors.white.withOpacity(0.08) : Colors.white;

        List<Widget> children = [];
        for (int index = 0; index < tabs.length; index++) {
          final bool selected = controller.index == index;
          children.add(
            SizedBox(
              width: segWidth,
              height: double.infinity,
              child: TactileRow(
                onTap: () => controller.animateTo(index),
                builder: (pressed) {
                  final Color baseBg = selected ? cs.primary.withOpacity(0.14) : Colors.transparent;
                  final Color bg = baseBg;

                  final Color baseTextColor = selected ? cs.primary : cs.onSurface.withOpacity(0.82);
                  final Color targetTextColor =
                      pressed ? Color.lerp(baseTextColor, Colors.white, 0.22) ?? baseTextColor : baseTextColor;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(innerRadius),
                    ),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: targetTextColor),
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        builder: (context, color, _) {
                          return Text(
                            tabs[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color ?? baseTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          if (index != tabs.length - 1) {
            children.add(const SizedBox(width: gap));
          }
        }

        return Container(
          height: outerHeight,
          decoration: BoxDecoration(
            color: shellBg,
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.all(innerPadding),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: innerAvailWidth),
                child: SizedBox(
                  width: rowWidth,
                  child: Row(children: children),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
