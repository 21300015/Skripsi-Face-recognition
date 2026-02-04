import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CameraFeedWidget extends StatefulWidget {
  final String esp32IP;
  final VoidCallback? onImageCaptured; // Callback when image is captured
  final bool showCaptureButton; // Whether to show capture button

  const CameraFeedWidget({
    required this.esp32IP,
    this.onImageCaptured,
    this.showCaptureButton = true,
    super.key,
  });

  @override
  State<CameraFeedWidget> createState() => _CameraFeedWidgetState();
}

class _CameraFeedWidgetState extends State<CameraFeedWidget> {
  Uint8List? _capturedImage;
  bool _isCapturing = false;
  String? _error;
  List<Uint8List> _recentFrames = []; // Store recent frames for selection
  int _selectedFrameIndex = 0;

  @override
  void initState() {
    super.initState();
    // No automatic capture - wait for user action
  }

  Future<void> _captureMultipleFrames() async {
    setState(() {
      _isCapturing = true;
      _error = null;
      _recentFrames.clear();
    });

    try {
      // Capture 3-4 frames in quick succession for user to choose best one
      for (int i = 0; i < 3; i++) {
        final frame = await _captureFrame();
        if (frame != null && mounted) {
          setState(() {
            _recentFrames.add(frame);
          });

          // Small delay between captures
          if (i < 2) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      if (_recentFrames.isNotEmpty && mounted) {
        setState(() {
          _capturedImage = _recentFrames[0]; // Show first frame by default
          _selectedFrameIndex = 0;
          _isCapturing = false;
        });

        // Notify parent that images are available
        widget.onImageCaptured?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Capture failed: $e';
          _isCapturing = false;
        });
      }
    }
  }

  Future<Uint8List?> _captureFrame() async {
    try {
      final captureUrl = 'http://${widget.esp32IP}/api/camera/capture';

      final response = await http
          .get(Uri.parse(captureUrl), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return null;
    }
  }

  void _selectFrame(int index) {
    if (index < _recentFrames.length) {
      setState(() {
        _selectedFrameIndex = index;
        _capturedImage = _recentFrames[index];
      });
      widget.onImageCaptured?.call();
    }
  }

  Uint8List? get selectedImage => _capturedImage;

  @override
  void dispose() {
    // Clear frames to free memory
    _recentFrames.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 350,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Main image display area
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                color: Colors.grey[100],
              ),
              child: _buildImageDisplay(),
            ),
          ),

          // Frame selection thumbnails (if multiple frames available)
          if (_recentFrames.length > 1)
            Container(
              height: 70,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  const Text(
                    'Select best frame:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _recentFrames.asMap().entries.map((entry) {
                      int index = entry.key;
                      Uint8List frame = entry.value;
                      bool isSelected = index == _selectedFrameIndex;

                      return GestureDetector(
                        onTap: () => _selectFrame(index),
                        child: Container(
                          width: 50,
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey,
                              width: isSelected ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(frame, fit: BoxFit.cover),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Control buttons
          if (widget.showCaptureButton)
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _captureMultipleFrames,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(
                      _isCapturing ? 'Capturing...' : 'Capture Frames',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageDisplay() {
    if (_isCapturing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Capturing frames from ESP32...',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              'Please wait...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _captureMultipleFrames,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_capturedImage != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: Stack(
          children: [
            Image.memory(
              _capturedImage!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
            // Show selection indicator
            if (_recentFrames.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Frame ${_selectedFrameIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'ESP32 Camera Preview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap "Capture Frames" to take multiple photos\nand select the best one',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
