/// User profile in Supabase users table; Firebase Auth owns auth.
class UserProfile {
  const UserProfile({
    required this.uid,
    this.name = '',
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.city,
    this.address,
    this.role = 'user',
    this.isApproved = false,
    this.isVerified = false,
    this.verificationStatus = 'NONE',
    this.isActive = false,
    this.policeId,
    this.assignedIntersection,
    this.assignedIntersectionId,
    this.intersectionLatitude,
    this.intersectionLongitude,
    this.drivingLicense,
    this.vehicleType,
    this.vehicleNumber,
    this.licenseImagePath,
    this.fcmTokens = const {},
  });

  /// Firebase Auth uid; join key for other tables.
  final String uid;
  final String name;
  final String fullName;
  final String email;
  final String phone;
  final String? city;
  final String? address;

  final String role;

  final bool isApproved;
  final bool isVerified;
  final String verificationStatus;
  final bool isActive;

  final String? policeId;
  final String? assignedIntersection;
  final String? assignedIntersectionId;
  final double? intersectionLatitude;
  final double? intersectionLongitude;

  final String? drivingLicense;
  final String? vehicleType;
  final String? vehicleNumber;
  final String? licenseImagePath;

  final Map<String, dynamic> fcmTokens;

  bool get isAdmin => role == 'admin';
  bool get isDriver => role == 'driver';
  bool get isTrafficOfficer => role == 'traffic_police';
  bool get isHospital => role == 'hospital';

  /// Verified officer with admin-granted police role.
  bool get isVerifiedOfficer =>
      isTrafficOfficer &&
      isVerified &&
      verificationStatus == 'APPROVED';

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (fullName.trim().isNotEmpty) return fullName.trim();
    return 'User';
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    double? asDouble(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value');

    bool asBool(Object? value) =>
        value == true || value == 1 || value == 'true';

    String asText(Object? value) => value?.toString() ?? '';

    final tokens = map['fcm_tokens'] ?? map['fcmTokens'];

    return UserProfile(
      uid: asText(map['firebase_uid'] ?? map['uid']),
      name: asText(map['name']),
      fullName: asText(map['full_name'] ?? map['fullName']),
      email: asText(map['email']),
      phone: asText(map['phone']),
      city: map['city']?.toString(),
      address: map['address']?.toString(),
      role: asText(map['role']).isEmpty ? 'user' : asText(map['role']),
      isApproved: asBool(map['is_approved'] ?? map['isApproved']),
      isVerified: asBool(map['is_verified'] ?? map['isVerified']),
      verificationStatus: asText(
        map['verification_status'] ?? map['verificationStatus'],
      ).isEmpty
          ? 'NONE'
          : asText(map['verification_status'] ?? map['verificationStatus']),
      isActive: asBool(map['is_active'] ?? map['isActive']),
      policeId: map['police_id']?.toString() ?? map['policeId']?.toString(),
      assignedIntersection:
          map['assigned_intersection']?.toString() ??
          map['assignedIntersection']?.toString(),
      assignedIntersectionId:
          map['assigned_intersection_id']?.toString() ??
          map['assignedIntersectionId']?.toString(),
      intersectionLatitude: asDouble(
        map['intersection_lat'] ?? map['intersectionLatitude'],
      ),
      intersectionLongitude: asDouble(
        map['intersection_lng'] ?? map['intersectionLongitude'],
      ),
      drivingLicense:
          map['driving_license']?.toString() ??
          map['drivingLicense']?.toString(),
      vehicleType:
          map['vehicle_type']?.toString() ?? map['vehicleType']?.toString(),
      vehicleNumber:
          map['vehicle_number']?.toString() ?? map['vehicleNumber']?.toString(),
      licenseImagePath:
          map['license_image_path']?.toString() ??
          map['licenseImagePath']?.toString(),
      fcmTokens: tokens is Map
          ? tokens.map((key, value) => MapEntry('$key', value))
          : const {},
    );
  }

  /// Camel-case view for older Firestore-shaped screens.
  Map<String, dynamic> toData() => {
    'uid': uid,
    'name': name,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'city': city,
    'address': address,
    'role': role,
    'isApproved': isApproved,
    'isVerified': isVerified,
    'verificationStatus': verificationStatus,
    'isActive': isActive,
    'policeId': policeId,
    'assignedIntersection': assignedIntersection,
    'assignedIntersectionId': assignedIntersectionId,
    'intersectionLatitude': intersectionLatitude,
    'intersectionLongitude': intersectionLongitude,
    'drivingLicense': drivingLicense,
    'vehicleType': vehicleType,
    'vehicleNumber': vehicleNumber,
    'licenseImagePath': licenseImagePath,
    'fcmTokens': fcmTokens,
  };

  /// Supabase row (snake_case); omits nulls so partial updates don't blank columns.
  Map<String, dynamic> toRow() => {
    'firebase_uid': uid,
    'name': name,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    if (city != null) 'city': city,
    if (address != null) 'address': address,
    'role': role,
    'is_approved': isApproved,
    'is_verified': isVerified,
    'verification_status': verificationStatus,
    'is_active': isActive,
    if (policeId != null) 'police_id': policeId,
    if (assignedIntersection != null)
      'assigned_intersection': assignedIntersection,
    if (assignedIntersectionId != null)
      'assigned_intersection_id': assignedIntersectionId,
    if (intersectionLatitude != null) 'intersection_lat': intersectionLatitude,
    if (intersectionLongitude != null)
      'intersection_lng': intersectionLongitude,
    if (drivingLicense != null) 'driving_license': drivingLicense,
    if (vehicleType != null) 'vehicle_type': vehicleType,
    if (vehicleNumber != null) 'vehicle_number': vehicleNumber,
    if (licenseImagePath != null) 'license_image_path': licenseImagePath,
  };

  UserProfile copyWith({
    String? name,
    String? fullName,
    String? email,
    String? phone,
    String? city,
    String? address,
    String? role,
    bool? isApproved,
    bool? isVerified,
    String? verificationStatus,
    bool? isActive,
    String? policeId,
    String? assignedIntersection,
    String? assignedIntersectionId,
    double? intersectionLatitude,
    double? intersectionLongitude,
    String? drivingLicense,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseImagePath,
    Map<String, dynamic>? fcmTokens,
  }) => UserProfile(
    uid: uid,
    name: name ?? this.name,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    city: city ?? this.city,
    address: address ?? this.address,
    role: role ?? this.role,
    isApproved: isApproved ?? this.isApproved,
    isVerified: isVerified ?? this.isVerified,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    isActive: isActive ?? this.isActive,
    policeId: policeId ?? this.policeId,
    assignedIntersection: assignedIntersection ?? this.assignedIntersection,
    assignedIntersectionId:
        assignedIntersectionId ?? this.assignedIntersectionId,
    intersectionLatitude:
        intersectionLatitude ?? this.intersectionLatitude,
    intersectionLongitude:
        intersectionLongitude ?? this.intersectionLongitude,
    drivingLicense: drivingLicense ?? this.drivingLicense,
    vehicleType: vehicleType ?? this.vehicleType,
    vehicleNumber: vehicleNumber ?? this.vehicleNumber,
    licenseImagePath: licenseImagePath ?? this.licenseImagePath,
    fcmTokens: fcmTokens ?? this.fcmTokens,
  );
}
