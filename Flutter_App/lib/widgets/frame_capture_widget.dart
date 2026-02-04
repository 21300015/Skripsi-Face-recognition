import 'package:flutter/material.dart';
import 'dart:async';

class FrameCaptureWidget extends StatefulWidget {
  final String esp32IP;
  final bool isActive;
  final Function(String)?
  onFrameCaptured; // Callback untuk frame yang di-capture

  const FrameCaptureWidget({
    required this.esp32IP,
    required this.isActive,
    this.onFrameCaptured,
    super.key,
  });

  @override
  State<FrameCaptureWidget> createState() => _FrameCaptureWidgetState();
}

class _FrameCaptureWidgetState extends State<FrameCaptureWidget> {
  Timer? _frameTimer;
  String _currentImageUrl = '';
  bool _isLoading = false;
  int _frameCount = 0;
  bool _autoCapture = true; // Toggle untuk auto capture

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startFrameCapture();
    }
  }

  @override
  void didUpdateWidget(FrameCaptureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _startFrameCapture();
      } else {
        _stopFrameCapture();
      }
    }
  }

  void _startFrameCapture() {
    _frameTimer?.cancel();

    // Capture frame immediately
    _captureFrame();

    // Start auto-capture every 3 seconds if enabled
    if (_autoCapture) {
      _frameTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && widget.isActive && _autoCapture) {
          _captureFrame();
        }
      });
    }
  }

  void _stopFrameCapture() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  void _captureFrame() {
    if (!mounted || !widget.isActive) return;

    setState(() {
      _isLoading = true;
    });

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final frameUrl = 'http://${widget.esp32IP}/api/camera/capture?t=$timestamp';

    // Frame capture debug info removed

    setState(() {
      _currentImageUrl = frameUrl;
      _frameCount++;
      _isLoading = false;
    });
  }

  void _manualCapture() {
    _captureFrame();
    // Notify parent widget about the captured frame
    if (widget.onFrameCaptured != null) {
      widget.onFrameCaptured!(_currentImageUrl);
    }
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCapture = !_autoCapture;
      if (_autoCapture) {
        _startFrameCapture();
      } else {
        _frameTimer?.cancel();
        _frameTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _stopFrameCapture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (!widget.isActive) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'ESP32 Camera Preview',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Akan aktif saat memilih ESP Camera',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentImageUrl.isEmpty) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 8),
              Text(
                'Menghubungkan ke ESP32 Camera...',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mode Frame-by-Frame untuk Enrollment',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Frame capture image
        Image.network(
          _currentImageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.black87,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.red.shade100,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Gagal memuat frame camera',
                      style: TextStyle(color: Colors.red),
                    ),
                    Text(
                      'Pastikan ESP32 aktif dan terhubung',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Capture mode indicator
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'CAPTURE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Frame counter
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Frame: $_frameCount',
              style: const TextStyle(color: Colors.white, fontSize: 9),
            ),
          ),
        ),

        // Capture controls
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Auto capture toggle
              ElevatedButton.icon(
                onPressed: _toggleAutoCapture,
                icon: Icon(
                  _autoCapture ? Icons.pause : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  _autoCapture ? 'Pause' : 'Auto',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _autoCapture ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(80, 32),
                ),
              ),
              // Manual capture button
              ElevatedButton.icon(
                onPressed: _manualCapture,
                icon: const Icon(Icons.camera, size: 16),
                label: const Text('Capture', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(90, 32),
                ),
              ),
            ],
          ),
        ),

        // Loading overlay
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
