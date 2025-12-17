import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

// Simple camera capture page for Android/Windows that returns a captured image path.
// - Android: prefers back camera.
// - Windows: uses the first available camera.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      try {
        c.dispose();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      _createController(c.description);
    }
  }

  Future<void> _init() async {
    if (kIsWeb) {
      setState(() {
        _error = 'Web not supported';
        _initializing = false;
      });
      return;
    }
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (!(isAndroid || isWindows)) {
      setState(() {
        _error = 'Unsupported platform';
        _initializing = false;
      });
      return;
    }

    try {
      if (isAndroid) {
        final st = await ph.Permission.camera.request();
        if (!st.isGranted) {
          setState(() {
            _error = 'Camera permission not granted';
            _initializing = false;
          });
          return;
        }
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _error = 'No camera found';
          _initializing = false;
        });
        return;
      }

      CameraDescription selected;
      if (isAndroid) {
        selected = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first,
        );
      } else {
        selected = cams.first;
      }

      await _createController(selected);
    } catch (e) {
      setState(() {
        _error = 'Camera error: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _createController(CameraDescription desc) async {
    try {
      final next = CameraController(desc, ResolutionPreset.high, enableAudio: false);
      await next.initialize();
      if (!mounted) return;
      setState(() {
        _controller = next;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Initialize failed: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final x = await c.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(x.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Capture failed: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _controller;

    if (_initializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (c == null || !c.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: const Center(child: Text('Camera not initialized')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Camera'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(c)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _capturing ? cs.primary.withOpacity(0.6) : cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

