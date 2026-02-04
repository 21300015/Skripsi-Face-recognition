import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';

class ESP32Service {
  static String _esp32IP = "192.168.4.1"; // Default ESP32 AP IP
  static const String _ipBoxName = 'esp32_settings';
  static const String _ipKey = 'esp32_ip';

  // Initialize IP from storage
  static Future<void> initializeIP() async {
    try {
      final box = await Hive.openBox(_ipBoxName);
      final savedIP = box.get(_ipKey);
      if (savedIP != null && savedIP.isNotEmpty) {
        _esp32IP = savedIP;
      }
    } catch (e) {
      // Error loading saved IP - silently fail
    }
  }

  // Getter for current IP
  static String get currentIP => _esp32IP;

  // Setter for ESP32 IP address with persistence
  static Future<void> setESP32IP(String ip) async {
    _esp32IP = ip;
    try {
      final box = await Hive.openBox(_ipBoxName);
      await box.put(_ipKey, ip);
    } catch (e) {
      // Error saving IP - silently fail
    }
  }

  // Getter for ESP32 IP address (backward compatibility)
  static String getESP32IP() {
    return _esp32IP;
  }

  // ========================================
  // LIVE CAMERA ENROLLMENT - OPTIMIZED API
  // ========================================

  /// Start face enrollment using ESP32 live camera only
  static Future<bool> startEnrollment(String userName) async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/enroll/start");
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'name=${Uri.encodeComponent(userName)}',
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Cancel current enrollment
  static Future<bool> cancelEnrollment() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/enroll/cancel");
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Clear all enrolled faces from ESP32
  static Future<bool> clearEnrolledFaces() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/enroll/clear");
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get enrollment status
  static Future<Map<String, dynamic>?> getEnrollmentStatus() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/enroll/status");
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ========================================
  // SYSTEM STATUS AND CONTROL
  // ========================================

  /// Get ESP32 system status
  static Future<Map<String, dynamic>?> getSystemStatus() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/status");
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Unlock door manually
  static Future<bool> unlockDoor() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/door/unlock");
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get access logs from ESP32
  static Future<List<Map<String, dynamic>>> getAccessLogs() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/logs");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get activities from ESP32 (alias for getAccessLogs for backward compatibility)
  static Future<List<Map<String, dynamic>>> getActivities() async {
    return await getAccessLogs();
  }

  /// Get live camera stream URL (MJPEG stream on port 81) - UPDATED TO /CAMWEB
  static String getCameraStreamUrl() {
    return "http://$_esp32IP/camweb";
  }

  /// Start live feed - pauses face recognition on ESP32
  static Future<bool> startLiveFeed() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/livefeed/start");
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Stop live feed - resumes face recognition on ESP32
  static Future<bool> stopLiveFeed() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/livefeed/stop");
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ========================================
  // LOCAL USER MANAGEMENT
  // ========================================

  /// Add user to local storage (Hive)
  static Future<void> addUser(User user) async {
    try {
      final userBox = Hive.box<User>('users');
      await userBox.put(user.id, user);
    } catch (e) {
      rethrow;
    }
  }

  /// Get all users from local storage
  static Future<List<User>> getUsers() async {
    try {
      final userBox = Hive.box<User>('users');
      return userBox.values.toList();
    } catch (e) {
      return [];
    }
  }

  /// Update user in local storage
  static Future<void> updateUser(User user) async {
    try {
      final userBox = Hive.box<User>('users');
      await userBox.put(user.id, user);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete user from local storage
  static Future<bool> deleteUser(String userId) async {
    try {
      final userBox = Hive.box<User>('users');
      int userIdInt = int.tryParse(userId) ?? 0;
      await userBox.delete(userIdInt);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ========================================
  // CONNECTIVITY TEST
  // ========================================

  /// Test ESP32 connectivity
  static Future<bool> testConnection() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/status");
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Check ESP32 connection (alias for testConnection)
  static Future<bool> checkConnection() async {
    return await testConnection();
  }

  /// Delete user from ESP32 by name
  static Future<bool> deleteUserByName(String userName) async {
    try {
      final url = Uri.parse(
        "http://$_esp32IP/api/users?name=${Uri.encodeComponent(userName)}",
      );
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Ping ESP32 with timeout
  static Future<bool> pingESP32() async {
    try {
      final socket = await Socket.connect(
        _esp32IP,
        80,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ========================================
  // UTILITY METHODS
  // ========================================

  /// Get network info for ESP32 connection
  static Map<String, String> getNetworkInfo() {
    return {
      'esp32_ip': _esp32IP,
      'camera_stream': getCameraStreamUrl(),
      'api_base': "http://$_esp32IP/api",
    };
  }

  /// Check if IP address is valid
  static bool isValidIP(String ip) {
    final regex = RegExp(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$');
    if (!regex.hasMatch(ip)) return false;

    final parts = ip.split('.');
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  // ========================================
  // LEGACY SUPPORT (for backward compatibility)
  // ========================================

  /// Clear enrollment cache (legacy method)
  static Future<bool> clearEnrollmentCache() async {
    // For backward compatibility - not needed in optimized version
    return true;
  }

  /// Enroll user face with ESP32 camera (legacy wrapper)
  static Future<String?> enrollUserFaceESP32Camera(
    String userId,
    String userName,
  ) async {
    final success = await startEnrollment(userName);
    return success ? 'enrolled_via_esp32_camera' : null;
  }

  /// Sync users method (legacy)
  static Future<bool> syncUsers(List<User> users) async {
    // For backward compatibility - not needed in standalone mode
    return true;
  }

  // ========================================
  // USER SYNC METHODS
  // ========================================

  /// Sync local users to ESP32
  static Future<bool> syncUsersToESP32(List<User> localUsers) async {
    try {
      for (var user in localUsers) {
        final success = await addUserToESP32(user);
        if (!success) {
          return false;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync users from ESP32 to local storage
  static Future<List<User>> syncUsersFromESP32() async {
    try {
      final esp32Users = await getUsersFromESP32();

      // Add/update users in local storage
      for (var esp32User in esp32Users) {
        await addUser(esp32User); // This will update if user exists
      }

      return esp32Users;
    } catch (e) {
      return [];
    }
  }

  /// Add user to ESP32
  static Future<bool> addUserToESP32(User user) async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/users");
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'name': user.nama,
              'jabatan': user.jabatan,
              'departemen': user.departemen,
              'masaBerlaku': user.masaBerlaku.toIso8601String().split(
                'T',
              )[0], // YYYY-MM-DD format
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get users from ESP32
  static Future<List<User>> getUsersFromESP32() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/users");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.map((userData) {
            return User(
              id: userData['id'] ?? 0,
              nama: userData['name'] ?? '',
              jabatan: userData['jabatan'] ?? '',
              departemen: userData['departemen'] ?? '',
              masaBerlaku: DateTime.parse(
                userData['masaBerlaku'] ?? '2025-12-31',
              ),
              thumbnailPath: '', // ESP32 doesn't store images
            );
          }).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Update user on ESP32
  static Future<bool> updateUserOnESP32(User user) async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/users");
      final response = await http
          .put(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'id': user.id.toString(),
              'name': user.nama,
              'jabatan': user.jabatan,
              'departemen': user.departemen,
              'masaBerlaku': user.masaBerlaku.toIso8601String().split('T')[0],
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Delete user from ESP32
  static Future<bool> deleteUserFromESP32(String userId) async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/users?id=$userId");
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ========================================
  // MEMORY STATUS AND OPTIMIZATION
  // ========================================

  /// Get ESP32 memory status for optimization monitoring
  static Future<Map<String, dynamic>?> getMemoryStatus() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/memory");
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ========================================
  // PROFILE IMAGE METHODS (SD Card Storage)
  // Uploads directly to ESP32 SD card - memory efficient
  // Images are resized to <200KB before upload
  // ========================================

  /// Resize image to target size (max 200KB, 400x400 pixels)
  /// Returns the resized image file path
  static Future<File> _resizeImageForUpload(
    File imageFile,
    String username,
  ) async {
    try {
      // Read original image
      final bytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        print('[RESIZE] Failed to decode image, using original');
        return imageFile;
      }

      // Target: 400x400 max dimension, JPEG quality 85
      const int maxDimension = 400;
      const int targetQuality = 85;
      const int maxSizeBytes = 200 * 1024; // 200KB

      // Calculate new dimensions maintaining aspect ratio
      int newWidth, newHeight;
      if (originalImage.width > originalImage.height) {
        newWidth = originalImage.width > maxDimension
            ? maxDimension
            : originalImage.width;
        newHeight = (originalImage.height * newWidth / originalImage.width)
            .round();
      } else {
        newHeight = originalImage.height > maxDimension
            ? maxDimension
            : originalImage.height;
        newWidth = (originalImage.width * newHeight / originalImage.height)
            .round();
      }

      // Resize image
      final resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );

      // Encode to JPEG with quality
      var quality = targetQuality;
      List<int> jpegBytes = img.encodeJpg(resizedImage, quality: quality);

      // If still too large, reduce quality iteratively
      while (jpegBytes.length > maxSizeBytes && quality > 30) {
        quality -= 10;
        jpegBytes = img.encodeJpg(resizedImage, quality: quality);
        print(
          '[RESIZE] Reducing quality to $quality, size: ${jpegBytes.length} bytes',
        );
      }

      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final resizedFile = File(
        '${tempDir.path}/profile_${username}_resized.jpg',
      );
      await resizedFile.writeAsBytes(jpegBytes);

      print(
        '[RESIZE] Original: ${bytes.length} bytes -> Resized: ${jpegBytes.length} bytes (${newWidth}x$newHeight, q:$quality)',
      );

      return resizedFile;
    } catch (e) {
      print('[RESIZE] Error resizing image: $e, using original');
      return imageFile;
    }
  }

  /// Upload profile image to ESP32 SD card
  /// Image is automatically resized to <200KB before upload
  /// Returns true if successful
  static Future<bool> uploadProfileImage(
    String username,
    File imageFile,
  ) async {
    try {
      // Resize image before upload (max 200KB, 400x400)
      final resizedFile = await _resizeImageForUpload(imageFile, username);
      final fileSize = await resizedFile.length();
      print(
        '[UPLOAD] Uploading profile image for $username, size: $fileSize bytes',
      );

      final url = Uri.parse("http://$_esp32IP/api/profile/upload");

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add username field
      request.fields['username'] = username;

      // Add resized image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          resizedFile.path,
          filename: '$username.jpg',
        ),
      );

      // Send request with longer timeout for file upload
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      // Clean up temp file if different from original
      if (resizedFile.path != imageFile.path) {
        try {
          await resizedFile.delete();
        } catch (_) {}
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(
          '[UPLOAD] Upload result: ${data['success'] ? 'SUCCESS' : 'FAILED'}',
        );
        return data['success'] ?? false;
      }
      print('[UPLOAD] Upload failed with status: ${response.statusCode}');
      return false;
    } catch (e) {
      print('[UPLOAD] Error uploading profile image: $e');
      return false;
    }
  }

  /// Download profile image from ESP32 SD card
  /// Returns the downloaded file path, or null if failed
  static Future<String?> downloadProfileImage(
    String username,
    String savePath,
  ) async {
    try {
      final url = Uri.parse(
        "http://$_esp32IP/api/profile/download?username=${Uri.encodeComponent(username)}",
      );
      final response = await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Save to local file
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
        return savePath;
      }
      return null;
    } catch (e) {
      print('Error downloading profile image: $e');
      return null;
    }
  }

  /// Delete profile image from ESP32 SD card
  static Future<bool> deleteProfileImage(String username) async {
    try {
      final url = Uri.parse(
        "http://$_esp32IP/api/profile/delete?username=${Uri.encodeComponent(username)}",
      );
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error deleting profile image: $e');
      return false;
    }
  }

  /// List all profile images on ESP32 SD card
  static Future<List<Map<String, dynamic>>> listProfileImages() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/profile/list");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['profiles'] is List) {
          return List<Map<String, dynamic>>.from(data['profiles']);
        }
      }
      return [];
    } catch (e) {
      print('Error listing profile images: $e');
      return [];
    }
  }

  /// Get SD card status
  static Future<Map<String, dynamic>?> getSDCardStatus() async {
    try {
      final url = Uri.parse("http://$_esp32IP/api/sdcard/status");
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error getting SD card status: $e');
      return null;
    }
  }

  /// Sync profile image - upload to SD card if connected, download from SD card if exists
  /// Images are automatically resized to <200KB before upload
  static Future<String?> syncProfileImage(
    String username,
    String localPath,
  ) async {
    try {
      // Check if SD card is available
      final sdStatus = await getSDCardStatus();
      if (sdStatus == null || sdStatus['available'] != true) {
        print('[SYNC] SD card not available, using local storage');
        return localPath; // SD card not available, use local
      }

      final localFile = File(localPath);

      // Check if we have local image to upload
      if (localFile.existsSync()) {
        // Upload to ESP32 SD card (will be resized automatically)
        final uploaded = await uploadProfileImage(username, localFile);
        if (uploaded) {
          print('[SYNC] Profile uploaded to ESP32 SD card: $username');
        }
        return localPath;
      } else {
        // Try to download from ESP32 SD card
        final downloaded = await downloadProfileImage(username, localPath);
        if (downloaded != null) {
          print('[SYNC] Profile downloaded from ESP32 SD card: $username');
          return downloaded;
        }
      }

      return null;
    } catch (e) {
      print('[SYNC] Error syncing profile image: $e');
      return localPath; // Fallback to local path
    }
  }

  // ========================================
  // DEPRECATED METHODS - IMAGE ENROLLMENT NOT SUPPORTED
  // ========================================

  /// Image enrollment is NOT supported in memory-optimized live-camera-only mode
  @Deprecated(
    'Image enrollment is not supported. Use startEnrollment() instead.',
  )
  static Future<bool> enrollUserFaceWithImage(
    String userId,
    String userName,
    String jabatan,
    String departemen,
    String masaBerlaku,
    File imageFile,
  ) async {
    return false;
  }
}
