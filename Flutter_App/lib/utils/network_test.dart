// Network connectivity test for ESP32 camera access
// Tests various network configurations for Android emulator

import 'dart:io';
import 'package:http/http.dart' as http;

class NetworkTest {
  /// Test ESP32 connectivity from Android emulator
  static Future<Map<String, dynamic>> testESP32Connectivity() async {
    final results = <String, dynamic>{};

    // Test different IP configurations
    final testIPs = [
      '192.168.223.181', // Direct ESP32 IP
      '10.0.2.2', // Android emulator host machine gateway
      '10.0.2.15', // Android emulator default IP
    ];

    for (String ip in testIPs) {
      results[ip] = await _testSingleIP(ip);
    }

    return results;
  }

  static Future<Map<String, dynamic>> _testSingleIP(String ip) async {
    final result = <String, dynamic>{
      'ip': ip,
      'pingable': false,
      'webServer': false,
      'cameraEndpoint': false,
      'error': null,
    };

    try {
      // Test basic HTTP connectivity
      final response = await http
          .get(Uri.parse('http://$ip'))
          .timeout(const Duration(seconds: 5));

      result['webServer'] = response.statusCode == 200;

      if (result['webServer']) {
        // Test camera endpoint
        final cameraResponse = await http
            .get(Uri.parse('http://$ip/capture'))
            .timeout(const Duration(seconds: 5));

        result['cameraEndpoint'] = cameraResponse.statusCode == 200;
      }
    } catch (e) {
      result['error'] = e.toString();
    }

    return result;
  }

  /// Get recommended ESP32 IP for current platform
  static String getRecommendedESP32IP() {
    if (Platform.isAndroid) {
      // For Android emulator, might need different IP
      return '192.168.223.181'; // Start with direct IP, fallback if needed
    } else {
      return '192.168.223.181'; // Direct IP for other platforms
    }
  }
}
