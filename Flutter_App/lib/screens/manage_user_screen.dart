import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';
import '../models/user.dart';
import '../services/esp32_service.dart';
import 'add_user_screen.dart';

class ManageUserScreen extends StatefulWidget {
  const ManageUserScreen({super.key});

  @override
  _ManageUserScreenState createState() => _ManageUserScreenState();
}

class _ManageUserScreenState extends State<ManageUserScreen> {
  bool _isSyncing = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkConnectionAndSync();
  }

  /// Auto-sync when screen opens - check ESP32 connection and sync
  Future<void> _checkConnectionAndSync() async {
    setState(() => _isSyncing = true);

    try {
      final connected = await ESP32Service.checkConnection();
      setState(() => _isConnected = connected);

      if (connected) {
        await _syncWithESP32();
      }
    } catch (e) {
      setState(() => _isConnected = false);
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// Sync app data with ESP32 - App is master
  Future<void> _syncWithESP32() async {
    try {
      // Get users from ESP32
      final esp32Users = await ESP32Service.getUsersFromESP32();
      final box = Hive.box<User>('users');
      final localUsers = box.values.toList();

      // Merge: Add ESP32 users that don't exist locally (by name)
      for (var esp32User in esp32Users) {
        bool existsLocally = localUsers.any(
          (local) => local.nama.toLowerCase() == esp32User.nama.toLowerCase(),
        );

        if (!existsLocally) {
          // Add to local database
          box.add(esp32User);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced with ESP32 (${esp32Users.length} users on device)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silent fail for auto-sync
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _isConnected ? Icons.wifi : Icons.wifi_off,
              color: _isConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
          // Clear All button
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            onPressed: _isSyncing ? null : _clearAllUsers,
            tooltip: 'Clear All Users (ESP32 + App)',
          ),
          // Sync button
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _checkConnectionAndSync,
            tooltip: 'Sync with ESP32',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status Banner
          if (!_isConnected && !_isSyncing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Not connected to ESP32',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),

          // Add User Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddUserScreen(),
                      ),
                    );
                    // Auto-sync after adding user
                    if (result != null) {
                      _checkConnectionAndSync();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _clearAllUsers,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clear All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Users List
          Expanded(
            child: ValueListenableBuilder<Box<User>>(
              valueListenable: Hive.box<User>('users').listenable(),
              builder: (context, box, _) {
                final users = box.values.toList();

                if (users.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No users registered',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap "Add New User" to get started',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          backgroundImage:
                              user.thumbnailPath.isNotEmpty &&
                                  File(user.thumbnailPath).existsSync()
                              ? FileImage(File(user.thumbnailPath))
                              : null,
                          child:
                              user.thumbnailPath.isEmpty ||
                                  !File(user.thumbnailPath).existsSync()
                              ? Text(
                                  user.nama.isNotEmpty
                                      ? user.nama[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        title: Text(user.nama),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (user.jabatan.isNotEmpty ||
                                user.departemen.isNotEmpty)
                              Text('${user.jabatan} - ${user.departemen}'),
                            Text(
                              'Valid until: ${user.masaBerlaku.toString().split(' ')[0]}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Edit button
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editUser(user),
                              tooltip: 'Edit',
                            ),
                            // Delete button - ONE button, deletes from BOTH
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteUser(user),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _editUser(User user) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => AddUserScreen(userToEdit: user)),
    );

    if (result != null && result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Single delete - removes from both App and ESP32
  Future<void> _deleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to delete ${user.nama}?\n\n'
          'This will remove the user from the app and ESP32 face recognition.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSyncing = true);

    try {
      // 1. Delete from ESP32 first (by name since that's how faces are stored)
      bool esp32Deleted = false;
      if (_isConnected) {
        try {
          esp32Deleted = await ESP32Service.deleteUserByName(user.nama);

          // Also delete profile image from ESP32 SD card
          await ESP32Service.deleteProfileImage(user.nama);
        } catch (e) {
          // ESP32 delete failed, continue with local delete
        }
      }

      // 2. Delete from local Hive database
      try {
        if (user.isInBox) {
          await user.delete();
        }
      } catch (e) {
        // Ignore Hive errors
      }

      // Show result
      if (mounted) {
        String message = '${user.nama} deleted';
        if (_isConnected) {
          message += esp32Deleted
              ? ' from app and ESP32'
              : ' from app (ESP32 failed)';
        } else {
          message += ' from app (ESP32 offline)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: esp32Deleted || !_isConnected
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// Clear ALL users from both App and ESP32
  Future<void> _clearAllUsers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Clear All Users'),
        content: const Text(
          'This will DELETE ALL users from:\n\n'
          '• Flutter app (local database)\n'
          '• ESP32 face recognition\n\n'
          'This action cannot be undone!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSyncing = true);

    try {
      // 1. Clear ESP32
      bool esp32Cleared = false;
      if (_isConnected) {
        try {
          esp32Cleared = await ESP32Service.clearEnrolledFaces();
        } catch (e) {
          // ESP32 clear failed
        }
      }

      // 2. Clear local Hive database
      final box = Hive.box<User>('users');
      await box.clear();

      if (mounted) {
        String message = 'All users cleared';
        if (_isConnected) {
          message += esp32Cleared
              ? ' from app and ESP32'
              : ' from app (ESP32 failed)';
        } else {
          message += ' from app (ESP32 offline)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: esp32Cleared ? Colors.green : Colors.orange,
          ),
        );
      }

      // Refresh connection status
      _checkConnectionAndSync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }
}
