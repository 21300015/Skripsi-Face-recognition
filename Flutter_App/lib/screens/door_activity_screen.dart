import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/activity.dart';
import '../services/esp32_service.dart';
import 'package:intl/intl.dart';

class DoorActivityScreen extends StatefulWidget {
  const DoorActivityScreen({super.key});

  @override
  State<DoorActivityScreen> createState() => _DoorActivityScreenState();
}

class _DoorActivityScreenState extends State<DoorActivityScreen> {
  bool _isLoading = false;

  Future<void> _syncActivities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get activities from ESP32
      final activitiesData = await ESP32Service.getActivities();
      if (activitiesData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No activities found on ESP32'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Save activities to local database
      final box = Hive.box<Activity>('activities');
      int newActivities = 0;

      // ESP32 uses millis() which resets on reboot, so we use current time minus relative offset
      final now = DateTime.now();

      for (var activityData in activitiesData) {
        try {
          // ESP32 returns: username, status, success, confidence, timestamp (millis)
          final username = activityData['username'] ?? 'Unknown';
          final status = activityData['status'] ?? 'Unknown';
          final success = activityData['success'] == true;
          final confidence = (activityData['confidence'] ?? 0.0).toDouble();

          // Create a unique-ish time by using current time (logs are already ordered)
          final time = now.subtract(Duration(seconds: newActivities * 10));

          // Include success status in the display
          final displayStatus = success
              ? '✅ $status (${(confidence * 100).toStringAsFixed(0)}%)'
              : '❌ $status (${(confidence * 100).toStringAsFixed(0)}%)';

          final activity = Activity(
            status: displayStatus,
            username: username,
            time: time,
          );

          // Add to local DB
          await box.add(activity);
          newActivities++;
        } catch (e) {
          // Error processing activity handled silently
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced $newActivities activities from ESP32'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // Refresh UI
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearAllActivities() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Activities'),
        content: const Text(
          'Are you sure you want to delete all activity logs? This action cannot be undone.',
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
              'Delete All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final box = Hive.box<Activity>('activities');
      await box.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All activity logs cleared'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _syncActivities,
            tooltip: 'Sync from ESP32',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _isLoading ? null : _clearAllActivities,
            tooltip: 'Clear All Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          if (_isLoading) const LinearProgressIndicator(),

          // ESP32 info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ESP32 IP: ${ESP32Service.getESP32IP()} • Tap refresh to sync latest activities',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // Activity list
          Expanded(
            child: ValueListenableBuilder<Box<Activity>>(
              valueListenable: Hive.box<Activity>('activities').listenable(),
              builder: (context, box, _) {
                final activities = box.values.toList().reversed.toList();
                if (activities.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No activity logs found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap the refresh button to sync from ESP32',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                // Limit display to 50 most recent activities
                final displayActivities = activities.take(50).toList();
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: displayActivities.length,
                  itemBuilder: (context, idx) {
                    final activity = displayActivities[idx];
                    final isSuccess =
                        activity.status.contains('GRANTED') ||
                        activity.status.contains('UNLOCKED');

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isSuccess ? Icons.lock_open : Icons.lock,
                          color: isSuccess ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          activity.status,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: isSuccess
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'User: ${activity.username}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(activity.time)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        dense: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'delete') {
                              await activity.delete();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Activity deleted'),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
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

      // Floating action button for quick sync
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _syncActivities,
        tooltip: 'Sync Activities',
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.sync),
      ),
    );
  }
}
