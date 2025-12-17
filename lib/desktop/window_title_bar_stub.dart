import 'package:flutter/material.dart';

/// Web stub: WindowTitleBar is not needed on web (browser handles window chrome)
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key, this.leftChildren = const <Widget>[]});
  final List<Widget> leftChildren;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class WindowCaptionActions extends StatelessWidget {
  const WindowCaptionActions({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

