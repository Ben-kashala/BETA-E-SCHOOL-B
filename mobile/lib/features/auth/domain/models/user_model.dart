class UserModel {
  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final String? phone;
  final String? schoolCode;
  final String? studentId;
  final String? profilePicture;
  // Adresse (élève/parent) – optionnelle
  final String? address;
  final String? addressCity;
  final String? addressProvince;
  final String? addressCountry;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phone,
    this.schoolCode,
    this.studentId,
    this.profilePicture,
    this.address,
    this.addressCity,
    this.addressProvince,
    this.addressCountry,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final school = json['school'];
    final String? schoolCode = (json['school_code'] as String?) ??
        (school is Map ? (school['code'] as String?) : null);
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      firstName: (json['first_name'] as String?) ?? '',
      lastName: (json['last_name'] as String?) ?? '',
      role: json['role'] as String,
      phone: json['phone'] as String?,
      schoolCode: schoolCode,
      studentId: json['student_id'] as String?,
      profilePicture: json['profile_picture'] as String?,
      address: json['address'] as String?,
      addressCity: json['address_city'] as String? ?? json['city'] as String?,
      addressProvince: json['address_province'] as String? ?? json['province'] as String?,
      addressCountry: json['address_country'] as String? ?? json['country'] as String?,
    );
  }

  String get fullName => '$firstName $lastName';

  bool get isStudent => role == 'STUDENT';
  bool get isParent => role == 'PARENT';
  bool get isTeacher => role == 'TEACHER';
  bool get isAdmin => role == 'ADMIN';
  bool get isPromoter => role == 'PROMOTER';
}
