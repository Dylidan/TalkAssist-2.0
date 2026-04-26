import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() => _errorMessage = 'No cameras available.');
        }
        return;
      }

      final selectedCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        // Originally high, but hella laggy.
        ResolutionPreset.high,
        enableAudio: false,
        fps: 30,
      );
      _controller = controller;
      await controller.initialize();

      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Camera error: $e');
      }
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isTakingPicture) return;

    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to take picture: $e')));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildBody()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: ClipOval(
                  child: Material(
                    color: Colors.black45,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isInitialized)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: _takePicture,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
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

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controller;
    if (!_isInitialized || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return CameraPreview(controller);
  }
}
