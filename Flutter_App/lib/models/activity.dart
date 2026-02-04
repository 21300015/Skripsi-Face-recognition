import 'package:hive/hive.dart';

part 'activity.g.dart';

@HiveType(typeId: 1)
class Activity extends HiveObject {
  @HiveField(0)
  String status;

  @HiveField(1)
  String username;

  @HiveField(2)
  DateTime time;

  Activity({required this.status, required this.username, required this.time});
}
