import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/user.dart';
import 'models/activity.dart';
import 'screens/home_screen.dart';
import 'services/esp32_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(UserAdapter());
  Hive.registerAdapter(ActivityAdapter());
  await Hive.openBox<User>('users');
  await Hive.openBox<Activity>('activities');

  // Insert default users if database is empty
  final userBox = Hive.box<User>('users');
  if (userBox.isEmpty) {
    userBox.addAll([
      User(
        id: 1,
        nama: 'Roqhim',
        jabatan: 'Sales',
        departemen: 'Sales',
        masaBerlaku: DateTime(2025, 12, 31),
        thumbnailPath: '',
      ),
      User(
        id: 2,
        nama: 'Ikhsan',
        jabatan: 'Finance',
        departemen: 'Finance',
        masaBerlaku: DateTime(2025, 12, 31),
        thumbnailPath: '',
      ),
      User(
        id: 3,
        nama: 'Icha',
        jabatan: 'Accountant',
        departemen: 'Akunting',
        masaBerlaku: DateTime(2025, 12, 31),
        thumbnailPath: '',
      ),
      User(
        id: 4,
        nama: 'Adi',
        jabatan: 'HR Manager',
        departemen: 'HR',
        masaBerlaku: DateTime(2025, 12, 31),
        thumbnailPath: '',
      ),
      User(
        id: 5,
        nama: 'Rio',
        jabatan: 'Programmer',
        departemen: 'IT',
        masaBerlaku: DateTime(2025, 12, 31),
        thumbnailPath: '',
      ),
    ]);
  }
  // Add 5 sample activities if box is empty
  final activityBox = Hive.box<Activity>('activities');
  if (activityBox.isEmpty) {
    activityBox.addAll([
      Activity(
        status: 'Unlock',
        username: 'Roqhim',
        time: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      Activity(
        status: 'Unlock',
        username: 'Ikhsan',
        time: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
      Activity(
        status: 'Unlock',
        username: 'Icha',
        time: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      Activity(
        status: 'Unlock',
        username: 'Adi',
        time: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      Activity(
        status: 'Unlock',
        username: 'Rio',
        time: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);
  }

  // Initialize ESP32Service IP from storage
  await ESP32Service.initializeIP();

  runApp(AksesKontrolPintuApp());
}

class AksesKontrolPintuApp extends StatelessWidget {
  const AksesKontrolPintuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akses Kontrol Pintu',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
