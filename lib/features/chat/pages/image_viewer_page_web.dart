import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../shared/widgets/snackbar.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.images, this.initialIndex = 0});

  final List<String> images; // http urls or data urls (web)
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> with TickerProviderStateMixin {
  late final PageController _controller;
  late int _index;
  late final List<TransformationController> _zoomCtrls;
  late final AnimationController _zoomCtrl;
  VoidCallback? _zoomTick;

  double _dragDy = 0.0;
  double _bgOpacity = 1.0;
  bool _dragActive = false;
  double _animFrom = 0.0;
  late final AnimationController _restoreCtrl;
  Offset? _lastDoubleTapPos;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.isEmpty ? 0 : widget.images.length - 1);
    _controller = PageController(initialPage: _index);
    _zoomCtrls = List<TransformationController>.generate(
      widget.images.length,
      (_) => TransformationController(),
      growable: false,
    );
    _restoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_restoreCtrl.value);
        setState(() {
          _dragDy = _animFrom * (1 - t);
          _bgOpacity = 1.0 - math.min(_dragDy / 300.0, 0.7);
        });
      });
    _zoomCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 230));
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _zoomCtrls) {
      c.dispose();
    }
    _restoreCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  ImageProvider _providerFor(String src) {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return NetworkImage(src);
    }
    if (src.startsWith('data:')) {
      try {
        final i = src.indexOf('base64,');
        if (i != -1) return MemoryImage(base64Decode(src.substring(i + 7)));
      } catch (_) {}
    }
    return const AssetImage('assets/placeholder.png');
  }

  bool _canDragDismiss() {
    if (_index < 0 || _index >= _zoomCtrls.length) return true;
    final s = _zoomCtrls[_index].value.getMaxScaleOnAxis();
    return s >= 0.98 && s <= 1.02;
  }

  void _handleVerticalDragStart(DragStartDetails d) {
    _dragActive = _canDragDismiss();
    if (!_dragActive) return;
    _restoreCtrl.stop();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails d) {
    if (!_dragActive) return;
    final dy = d.delta.dy;
    if (dy <= 0 && _dragDy <= 0) return;
    setState(() {
      _dragDy = math.max(0.0, _dragDy + dy);
      _bgOpacity = 1.0 - math.min(_dragDy / 300.0, 0.7);
    });
  }

  void _handleVerticalDragEnd(DragEndDetails d) {
    if (!_dragActive) return;
    _dragActive = false;
    final v = d.primaryVelocity ?? 0.0;
    const dismissDistance = 140.0;
    const dismissVelocity = 900.0;
    if (_dragDy > dismissDistance || v > dismissVelocity) {
      Navigator.of(context).maybePop();
      return;
    }
    _animFrom = _dragDy;
    _restoreCtrl
      ..reset()
      ..forward();
  }

  void _animateZoomTo(
    TransformationController ctrl, {
    required double toScale,
    required double toTx,
    required double toTy,
  }) {
    _zoomCtrl.stop();
    if (_zoomTick != null) {
      _zoomCtrl.removeListener(_zoomTick!);
      _zoomTick = null;
    }
    final m = ctrl.value.clone();
    final fromScale = m.getMaxScaleOnAxis();
    final fromTx = m.storage[12];
    final fromTy = m.storage[13];
    final curve = CurvedAnimation(parent: _zoomCtrl, curve: Curves.easeOutCubic);
    _zoomTick = () {
      final t = curve.value;
      final s = fromScale + (toScale - fromScale) * t;
      final x = fromTx + (toTx - fromTx) * t;
      final y = fromTy + (toTy - fromTy) * t;
      ctrl.value = Matrix4.identity()
        ..translate(x, y)
        ..scale(s);
    };
    _zoomCtrl.addListener(_zoomTick!);
    _zoomCtrl.forward(from: 0);
  }

  void _handleDoubleTap(TapDownDetails d) {
    _lastDoubleTapPos = d.localPosition;
    final ctrl = _zoomCtrls[_index];
    final m = ctrl.value.clone();
    final s = m.getMaxScaleOnAxis();
    if (s > 1.2) {
      _animateZoomTo(ctrl, toScale: 1.0, toTx: 0.0, toTy: 0.0);
      return;
    }
    final pos = _lastDoubleTapPos ?? Offset.zero;
    final scale = 2.5;
    final dx = -pos.dx * (scale - 1);
    final dy = -pos.dy * (scale - 1);
    _animateZoomTo(ctrl, toScale: scale, toTx: dx, toTy: dy);
  }

  Future<void> _copyCurrent() async {
    final src = widget.images[_index];
    await Clipboard.setData(ClipboardData(text: src));
    if (!mounted) return;
    showAppSnackBar(context, message: 'Copied', type: NotificationType.success);
  }

  Future<void> _openCurrent() async {
    final src = widget.images[_index];
    final lower = src.toLowerCase();
    final isUrl = lower.startsWith('http://') || lower.startsWith('https://');
    if (!isUrl) return;
    await launchUrlString(src, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(_bgOpacity),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1}/${widget.images.length}'),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: _copyCurrent,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: '打开',
            onPressed: _openCurrent,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: GestureDetector(
        onVerticalDragStart: _handleVerticalDragStart,
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (ctx, i) {
              final src = widget.images[i];
              final ctrl = _zoomCtrls[i];
              return Center(
                child: GestureDetector(
                  onDoubleTapDown: _handleDoubleTap,
                  onDoubleTap: () {},
                  child: InteractiveViewer(
                    transformationController: ctrl,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Hero(
                      tag: 'img:$src',
                      child: Image(
                        image: _providerFor(src),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surface.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Failed to load image',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
