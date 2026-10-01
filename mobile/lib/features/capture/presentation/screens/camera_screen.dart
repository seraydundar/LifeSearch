import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Pops with the photo's local file path, or `null` if backed out; macOS routes through `camera_macos` since `camera` has no macOS impl.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Platform.isMacOS ? const _MacOSCameraScreen() : const _MobileCameraScreen();
  }
}

class _MobileCameraScreen extends StatefulWidget {
  const _MobileCameraScreen();

  @override
  State<_MobileCameraScreen> createState() => _MobileCameraScreenState();
}

class _MobileCameraScreenState extends State<_MobileCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Bu cihazda kullanılabilir bir kamera bulunamadı.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kameraya erişilemedi. Ayarlardan izin verildiğinden emin ol.');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (_) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf çekilemedi. Tekrar dene.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        _ShutterButton(isCapturing: _isCapturing, onTap: _capture),
      ],
    );
  }
}

class _MacOSCameraScreen extends StatefulWidget {
  const _MacOSCameraScreen();

  @override
  State<_MacOSCameraScreen> createState() => _MacOSCameraScreenState();
}

class _MacOSCameraScreenState extends State<_MacOSCameraScreen> {
  CameraMacOSController? _controller;
  bool _isCapturing = false;

  @override
  void dispose() {
    _controller?.destroy();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final bytes = (await controller.takePicture())?.bytes;
      if (bytes == null) throw CameraMacOSException(message: 'no bytes returned');

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes);

      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf çekilemedi. Tekrar dene.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraMacOSView(
            cameraMode: CameraMacOSMode.photo,
            enableAudio: false,
            pictureFormat: PictureFormat.jpg,
            fit: BoxFit.cover,
            onCameraInizialized: (controller) => setState(() => _controller = controller),
            // Init error comes through here, not a thrown exception — no separate _error state needed.
            onCameraLoading: (error) {
              if (error == null) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Kameraya erişilemedi. Ayarlardan izin verildiğinden emin ol.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          if (_controller != null) _ShutterButton(isCapturing: _isCapturing, onTap: _capture),
        ],
      ),
    );
  }
}

/// Shared capture button for both camera screens.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.isCapturing, required this.onTap});

  final bool isCapturing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCapturing ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
