import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

// Simple camera capture page for Android/Windows that returns a captured image path.
// - Prefers back camera on Android (main camera); on Windows picks first available.
// - Returns the temporary file path from camera plugin via Navigator.pop(context, path).
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _initializing = true;
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
      try { c.dispose(); } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      // Recreate controller with same camera
      final desc = c.description;
      _createController(desc);
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
    if (!(Platform.isAndroid || Platform.isWindows)) {
      setState(() {
        _error = 'Unsupported platform';
        _initializing = false;
      });
      return;
    }
    try {
      // Request camera permission on Android
      if (Platform.isAndroid) {
        final st = await ph.Permission.camera.request();
        if (!st.isGranted) {
          setState(() {
            _error = '未授予相机权限';
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
      if (Platform.isAndroid) {
        selected = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first,
        );
      } else {
        // Windows: pick first available
        selected = cams.first;
      }
      _cameras = cams;
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
      final c = CameraController(desc, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() {
        _controller = c;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Initialize failed: $e';
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('拍照'),
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: Text('相机未初始化', style: TextStyle(color: Colors.white70)));
    }
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(c)),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _shutterButton(onPressed: _onCapture),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shutterButton({required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: Colors.white.withOpacity(0.12),
        ),
        child: Center(
          child: Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onCapture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      setState(() => _error = 'Capture failed: $e');
    }
  }
}
