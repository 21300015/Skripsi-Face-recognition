class SystemStatus {
  final bool camera;
  final bool sdCard;
  final bool wifi;
  final int freeHeap;
  final int totalUsers;
  final int totalActivities;
  final String lastActivity;
  final bool doorUnlocked;

  SystemStatus({
    required this.camera,
    required this.sdCard,
    required this.wifi,
    required this.freeHeap,
    required this.totalUsers,
    required this.totalActivities,
    required this.lastActivity,
    required this.doorUnlocked,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      camera: json['camera'] ?? false,
      sdCard: json['sdCard'] ?? false,
      wifi: json['wifi'] ?? false,
      freeHeap: json['freeHeap'] ?? 0,
      totalUsers: json['totalUsers'] ?? 0,
      totalActivities: json['totalActivities'] ?? 0,
      lastActivity: json['lastActivity'] ?? '',
      doorUnlocked: json['doorUnlocked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'camera': camera,
      'sdCard': sdCard,
      'wifi': wifi,
      'freeHeap': freeHeap,
      'totalUsers': totalUsers,
      'totalActivities': totalActivities,
      'lastActivity': lastActivity,
      'doorUnlocked': doorUnlocked,
    };
  }
}
