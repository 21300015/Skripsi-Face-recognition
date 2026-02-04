import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Simple MJPEG stream viewer that parses multipart/x-mixed-replace stream
class MjpegViewer extends StatefulWidget {
  final String streamUrl;
  final BoxFit fit;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  const MjpegViewer({
    super.key,
    required this.streamUrl,
    this.fit = BoxFit.contain,
    this.loadingWidget,
    this.errorWidget,
  });

  @override
  State<MjpegViewer> createState() => _MjpegViewerState();
}

class _MjpegViewerState extends State<MjpegViewer> {
  Uint8List? _currentFrame;
  bool _isLoading = true;
  bool _hasError = false;
  StreamSubscription? _subscription;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  void _stopStream() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  Future<void> _startStream() async {
    _stopStream();

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      _client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        return;
      }

      // Parse MJPEG stream
      List<int> buffer = [];
      bool foundStart = false;

      _subscription = response.stream.listen(
        (List<int> chunk) {
          buffer.addAll(chunk);

          // Look for JPEG markers
          while (buffer.length > 2) {
            if (!foundStart) {
              // Look for JPEG start marker (0xFF 0xD8)
              int startIdx = -1;
              for (int i = 0; i < buffer.length - 1; i++) {
                if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
                  startIdx = i;
                  break;
                }
              }

              if (startIdx == -1) {
                // No start marker found, keep last byte in case it's 0xFF
                if (buffer.isNotEmpty && buffer.last == 0xFF) {
                  buffer = [buffer.last];
                } else {
                  buffer.clear();
                }
                break;
              }

              // Found start, remove everything before it
              buffer = buffer.sublist(startIdx);
              foundStart = true;
            }

            if (foundStart) {
              // Look for JPEG end marker (0xFF 0xD9)
              int endIdx = -1;
              for (int i = 2; i < buffer.length - 1; i++) {
                if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
                  endIdx = i + 2;
                  break;
                }
              }

              if (endIdx == -1) {
                // No end marker yet, wait for more data
                break;
              }

              // Extract complete JPEG frame
              final frame = Uint8List.fromList(buffer.sublist(0, endIdx));

              if (mounted) {
                setState(() {
                  _currentFrame = frame;
                  _isLoading = false;
                });
              }

              // Remove processed frame from buffer
              buffer = buffer.sublist(endIdx);
              foundStart = false;
            }
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          }
        },
        onDone: () {
          // Stream ended, could reconnect here
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorWidget ??
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, color: Colors.red, size: 40),
                SizedBox(height: 8),
                Text('Stream Error', style: TextStyle(color: Colors.red)),
              ],
            ),
          );
    }

    if (_isLoading || _currentFrame == null) {
      return widget.loadingWidget ??
          const Center(child: CircularProgressIndicator());
    }

    return Image.memory(_currentFrame!, fit: widget.fit, gaplessPlayback: true);
  }
}
