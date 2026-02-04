class FaceUser {
  final String id;
  final String name;
  final String email;
  final String jabatan; // Job position
  final DateTime expiryDate; // Masa berlaku
  final List<String>
  faceImagePaths; // Multiple face images for better recognition
  final DateTime createdAt;
  final DateTime lastAccess;
  final bool isActive;

  FaceUser({
    required this.id,
    required this.name,
    required this.email,
    required this.jabatan,
    required this.expiryDate,
    required this.faceImagePaths,
    required this.createdAt,
    required this.lastAccess,
    required this.isActive,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'jabatan': jabatan,
    'expiryDate': expiryDate.toIso8601String(),
    'faceImagePaths': faceImagePaths,
    'createdAt': createdAt.toIso8601String(),
    'lastAccess': lastAccess.toIso8601String(),
    'isActive': isActive,
  };

  factory FaceUser.fromJson(Map<String, dynamic> json) => FaceUser(
    id: json['id'],
    name: json['name'],
    email: json['email'],
    jabatan: json['jabatan'] ?? '',
    expiryDate:
        json['expiryDate'] != null
            ? DateTime.parse(json['expiryDate'])
            : DateTime.now().add(const Duration(days: 365)), // Default 1 year
    faceImagePaths: List<String>.from(json['faceImagePaths']),
    createdAt: DateTime.parse(json['createdAt']),
    lastAccess: DateTime.parse(json['lastAccess']),
    isActive: json['isActive'],
  );
}
