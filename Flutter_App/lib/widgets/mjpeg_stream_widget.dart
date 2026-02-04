import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MjpegStreamWidget extends StatefulWidget {
  final String esp32IP;
  final bool forceRestart; // Add parameter to force restart

  const MjpegStreamWidget({
    required this.esp32IP,
    this.forceRestart = false,
    super.key,
  });

  @override
  State<MjpegStreamWidget> createState() => _MjpegStreamWidgetState();
}

class _MjpegStreamWidgetState extends State<MjpegStreamWidget> {
  Uint8List? _currentFrame;
  bool _isStreaming = false;
  String? _error;
  StreamSubscription<List<int>>? _streamSubscription;
  http.Client? _client;
  int _frameCount = 0;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _startMjpegStream();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MjpegStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart stream if forceRestart flag changes or IP changes
    if (widget.forceRestart != oldWidget.forceRestart ||
        widget.esp32IP != oldWidget.esp32IP) {
      _stopStreaming();
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startMjpegStream();
        }
      });
    }
  }

  Future<void> _startMjpegStream() async {
    if (_isStreaming) return;

    setState(() {
      _isStreaming = true;
      _error = null;
      _frameCount = 0;
    });

    try {
      _client = http.Client();
      final streamUrl = 'http://${widget.esp32IP}:81/';

      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Accept'] = 'multipart/x-mixed-replace';

      final streamedResponse = await _client!.send(request);

      if (streamedResponse.statusCode == 200) {
        _streamSubscription = streamedResponse.stream.listen(
          _processMjpegData,
          onError: (error) {
            if (mounted) {
              setState(() {
                _error = 'Stream error: $error';
                _errorCount++;
              });
              _reconnect();
            }
          },
          onDone: () {
            if (mounted && _isStreaming) {
              _reconnect();
            }
          },
        );
      } else {
        throw Exception('HTTP ${streamedResponse.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection failed: $e';
          _errorCount++;
        });
        _reconnect();
      }
    }
  }

  List<int> _buffer = [];
  List<int> _jpegStart = [0xFF, 0xD8]; // JPEG start marker
  List<int> _jpegEnd = [0xFF, 0xD9]; // JPEG end marker

  void _processMjpegData(List<int> data) {
    _buffer.addAll(data);

    // Look for complete JPEG frames
    while (true) {
      // Find JPEG start
      int startIndex = -1;
      for (int i = 0; i <= _buffer.length - 2; i++) {
        if (_buffer[i] == _jpegStart[0] && _buffer[i + 1] == _jpegStart[1]) {
          startIndex = i;
          break;
        }
      }

      if (startIndex == -1) {
        // No start found, keep only last few bytes in case start is split
        if (_buffer.length > 100) {
          _buffer = _buffer.sublist(_buffer.length - 10);
        }
        break;
      }

      // Look for JPEG end after start
      int endIndex = -1;
      for (int i = startIndex + 2; i <= _buffer.length - 2; i++) {
        if (_buffer[i] == _jpegEnd[0] && _buffer[i + 1] == _jpegEnd[1]) {
          endIndex = i + 1;
          break;
        }
      }

      if (endIndex == -1) {
        // No end found yet, remove data before start and wait for more
        _buffer = _buffer.sublist(startIndex);
        break;
      }

      // Extract complete JPEG frame
      final frameData = Uint8List.fromList(
        _buffer.sublist(startIndex, endIndex + 1),
      );

      // Update UI with new frame
      if (mounted && _isStreaming) {
        setState(() {
          _currentFrame = frameData;
          _frameCount++;
          _error = null;
        });
      }

      // Remove processed frame from buffer
      _buffer = _buffer.sublist(endIndex + 1);
    }
  }

  void _stopStreaming() {
    setState(() {
      _isStreaming = false;
    });
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _client?.close();
    _client = null;
    _buffer.clear();
  }

  void _reconnect() {
    _stopStreaming();
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _startMjpegStream();
      }
    });
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'Frames: $_frameCount | Errors: $_errorCount',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              if (_isStreaming)
                const Text(
                  'Retrying...',
                  style: TextStyle(color: Colors.orange, fontSize: 10),
                )
              else
                const Text(
                  'Stream paused',
                  style: TextStyle(color: Colors.red, fontSize: 10),
                ),
            ],
          ),
        ),
      );
    }

    if (_currentFrame == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 8),
              Text(
                'Connecting to ESP32 camera...',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Slow refresh rate to prevent crashes',
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Show current frame
        Image.memory(
          _currentFrame!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        // Stream status overlay
        Positioned(
          top: 8,
          right: 8,
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
                  decoration: BoxDecoration(
                    color: _isStreaming ? Colors.red : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: const TextStyle(
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
      ],
    );
  }
}
