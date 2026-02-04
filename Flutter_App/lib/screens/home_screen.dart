import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/activity.dart';
import '../models/user.dart'; // Import User model
import '../services/esp32_service.dart'; // Import ESP32Service
import '../widgets/mjpeg_viewer.dart'; // Import MJPEG viewer
import 'manage_user_screen.dart'; // Import the ManageUserScreen
import 'door_activity_screen.dart'; // Import the DoorActivityScreen
import 'wifi_config_screen.dart'; // Import the WiFiConfigScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _liveFeedActive = false;
  String _esp32Ip = ESP32Service.getESP32IP();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  void _startLiveFeed() async {
    // MJPEG stream automatically pauses recognition on ESP32 when connected
    setState(() {
      _liveFeedActive = true;
    });
  }

  void _stopLiveFeed() async {
    setState(() {
      _liveFeedActive = false;
    });
    // Notify ESP32 to resume recognition
    await ESP32Service.stopLiveFeed();
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: _esp32Ip);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ESP32-CAM IP Address',
            hintText: 'e.g. 192.168.1.100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _esp32Ip = controller.text;
              });
              await ESP32Service.setESP32IP(
                _esp32Ip,
              ); // Update ESP32Service IP with persistence
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveDoorActivity({required String status, required String username}) {
    try {
      final box = Hive.box<Activity>('activities');
      final activity = Activity(
        status: status,
        username: username,
        time: DateTime.now(),
      );
      box.add(activity);
    } catch (e) {
      // Error saving activity - silently fail
    }
  }

  void _syncUsersToEsp32() async {
    if (_esp32Ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set ESP32-CAM IP address first!')),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Flutter app is the master - sync FROM Flutter TO ESP32
      final userBox = Hive.box<User>('users');
      final localUsers = userBox.values.toList();

      // Use the new bulk sync endpoint
      final syncSuccess = await ESP32Service.syncUsers(localUsers);

      Navigator.of(context).pop(); // Close loading dialog

      if (syncSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync successful! ${localUsers.length} users synchronized to ESP32',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync failed. Please check ESP32 connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SISTEM KEAMANAN MENGGUNAKAN',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'METODE FACE RECOGNITION UNTUK',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'KONTROL AKSES PINTU RUANGAN',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'TATA USAHA PADA SMK IT NURUL QOLBI',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        centerTitle: true,
        toolbarHeight:
            100, // Increase AppBar height to accommodate 4 lines of text
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          final cameraBoxSize = screenWidth < screenHeight
              ? screenWidth * 0.8 * 0.4
              : screenHeight * 0.8 * 0.4;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: screenHeight * 0.03),
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    height: screenHeight * 0.192, // reduce by 20%
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
                Center(
                  child: (_esp32Ip.isNotEmpty && _liveFeedActive)
                      ? SizedBox(
                          height: cameraBoxSize * 1.4, // increase by 40%
                          width: cameraBoxSize * 1.4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: MjpegViewer(
                              streamUrl: 'http://$_esp32Ip:81/',
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      : Container(
                          height: cameraBoxSize * 1.4,
                          width: cameraBoxSize * 1.4,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            'assets/offline.jpg',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 80,
                                  ),
                                ),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                // Live feed button - DIRECT /CAMWEB STREAM
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    icon: Icon(_liveFeedActive ? Icons.stop : Icons.camera_alt),
                    label: Text(
                      _liveFeedActive ? 'Stop Live Feed' : 'Start Live Feed',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _liveFeedActive
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      if (_esp32Ip.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Set ESP32 IP address first!'),
                          ),
                        );
                        return;
                      }

                      // Toggle live feed state
                      setState(() {
                        _liveFeedActive = !_liveFeedActive;
                      });

                      // Start or stop the live feed with timer refresh
                      if (_liveFeedActive) {
                        _startLiveFeed();
                      } else {
                        _stopLiveFeed();
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _liveFeedActive
                                ? 'Live feed started - Recognition PAUSED'
                                : 'Live feed stopped - Recognition RESUMED',
                          ),
                          backgroundColor: _liveFeedActive
                              ? Colors.green
                              : Colors.orange,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
                Center(
                  child: Text(
                    'ESP32-CAM IP: ${_esp32Ip.isNotEmpty ? _esp32Ip : 'Not set'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(
                  height: screenHeight * 0.06,
                ), // Increase space before buttons
                // First row of buttons (Unlock Door, Door Activity)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton(
                          onPressed: () async {
                            final usernameController = TextEditingController();
                            final passwordController = TextEditingController();
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Login Required'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: usernameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Username',
                                      ),
                                    ),
                                    TextField(
                                      controller: passwordController,
                                      decoration: const InputDecoration(
                                        labelText: 'Password',
                                      ),
                                      obscureText: true,
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      final username = usernameController.text
                                          .trim();
                                      final password = passwordController.text;
                                      if (username == 'admin' &&
                                          password == 'admin123') {
                                        Navigator.pop(context);
                                        // Networking: Send unlock request to ESP32-CAM
                                        if (_esp32Ip.isNotEmpty) {
                                          try {
                                            final success =
                                                await ESP32Service.unlockDoor();
                                            if (success) {
                                              _saveDoorActivity(
                                                status: 'Door Unlocked',
                                                username: username,
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Door unlocked and activity logged for $username!',
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Failed to unlock door.',
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text('Error: $e'),
                                                ),
                                              );
                                            }
                                          }
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Set ESP32-CAM IP address first!',
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Invalid username or password!',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('Unlock'),
                                  ),
                                ],
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15.0),
                          ),
                          child: const Text('Unlock Door'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DoorActivityScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15.0),
                          ),
                          child: const Text('Activity Logs'),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.02),
                // Second row of buttons (Manage User, Sync Data)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ManageUserScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15.0),
                          ),
                          child: const Text('Manage User'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync Data'),
                          onPressed: _syncUsersToEsp32,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.02),
                // WiFi Configuration button
                Center(
                  child: SizedBox(
                    width: screenWidth * 0.5,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.wifi),
                      label: const Text('WiFi Config'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WiFiConfigScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15.0),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
              ],
            ),
          );
        },
      ),
    );
  }
}
