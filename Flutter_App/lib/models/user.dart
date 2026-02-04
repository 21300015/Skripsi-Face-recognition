import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String nama;

  @HiveField(2)
  String jabatan;

  @HiveField(3)
  String departemen;

  @HiveField(4)
  DateTime masaBerlaku;

  @HiveField(5)
  String thumbnailPath;

  User({
    required this.id,
    required this.nama,
    required this.jabatan,
    required this.departemen,
    required this.masaBerlaku,
    required this.thumbnailPath,
  });
}
