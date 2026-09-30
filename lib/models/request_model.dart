// Dart models that map to the Supabase PostgreSQL tables.

// ──────────────────────────────────────────────────────────────────────────────
// Request status
// ──────────────────────────────────────────────────────────────────────────────
enum RequestStatus {
  pending,
  accepted,
  enRoute,
  arrived,
  completed,
  cancelled;

  static RequestStatus fromString(String value) {
    switch (value) {
      case 'accepted':   return RequestStatus.accepted;
      case 'en_route':   return RequestStatus.enRoute;
      case 'arrived':    return RequestStatus.arrived;
      case 'completed':  return RequestStatus.completed;
      case 'cancelled':  return RequestStatus.cancelled;
      default:           return RequestStatus.pending;
    }
  }

  String toDbString() {
    switch (this) {
      case RequestStatus.pending:   return 'pending';
      case RequestStatus.accepted:  return 'accepted';
      case RequestStatus.enRoute:   return 'en_route';
      case RequestStatus.arrived:   return 'arrived';
      case RequestStatus.completed: return 'completed';
      case RequestStatus.cancelled: return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case RequestStatus.pending:   return 'Waiting for driver…';
      case RequestStatus.accepted:  return 'Driver accepted';
      case RequestStatus.enRoute:   return 'Driver on the way';
      case RequestStatus.arrived:   return 'Driver arrived';
      case RequestStatus.completed: return 'Completed';
      case RequestStatus.cancelled: return 'Cancelled';
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// AmbulanceRequest  ←→  requests table
// ──────────────────────────────────────────────────────────────────────────────
class AmbulanceRequest {
  final String id;
  final String userFirebaseUid;
  final String? driverId; // uuid FK → drivers.id
  final RequestStatus status;
  final String ambulanceType;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double destinationLat;
  final double destinationLng;
  final String destinationAddress;
  final int estimatedFare;
  final double distanceKm;
  final String userName;
  final String userPhone;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  // Joined from drivers table (populated when driverId != null)
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;

  const AmbulanceRequest({
    required this.id,
    required this.userFirebaseUid,
    this.driverId,
    required this.status,
    required this.ambulanceType,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAddress,
    required this.estimatedFare,
    required this.distanceKm,
    required this.userName,
    required this.userPhone,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
  });

  factory AmbulanceRequest.fromMap(Map<String, dynamic> map) {
    final driver = map['drivers'] as Map<String, dynamic>?;
    return AmbulanceRequest(
      id:                 map['id'] as String,
      userFirebaseUid:    map['user_firebase_uid'] as String,
      driverId:           map['driver_id'] as String?,
      status:             RequestStatus.fromString(map['status'] as String),
      ambulanceType:      map['ambulance_type'] as String,
      pickupLat:          (map['pickup_lat'] as num).toDouble(),
      pickupLng:          (map['pickup_lng'] as num).toDouble(),
      pickupAddress:      map['pickup_address'] as String,
      destinationLat:     (map['destination_lat'] as num).toDouble(),
      destinationLng:     (map['destination_lng'] as num).toDouble(),
      destinationAddress: map['destination_address'] as String,
      estimatedFare:      map['estimated_fare'] as int,
      distanceKm:         (map['distance_km'] as num).toDouble(),
      userName:           map['user_name'] as String,
      userPhone:          map['user_phone'] as String,
      createdAt:          DateTime.parse(map['created_at'] as String),
      acceptedAt:         map['accepted_at'] != null
                            ? DateTime.parse(map['accepted_at'] as String)
                            : null,
      completedAt:        map['completed_at'] != null
                            ? DateTime.parse(map['completed_at'] as String)
                            : null,
      driverName:         driver?['name'] as String?,
      driverPhone:        driver?['phone'] as String?,
      driverLat:          driver != null && driver['current_lat'] != null
                            ? (driver['current_lat'] as num).toDouble()
                            : null,
      driverLng:          driver != null && driver['current_lng'] != null
                            ? (driver['current_lng'] as num).toDouble()
                            : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'user_firebase_uid':    userFirebaseUid,
    'status':               status.toDbString(),
    'ambulance_type':       ambulanceType,
    'pickup_lat':           pickupLat,
    'pickup_lng':           pickupLng,
    'pickup_address':       pickupAddress,
    'destination_lat':      destinationLat,
    'destination_lng':      destinationLng,
    'destination_address':  destinationAddress,
    'estimated_fare':       estimatedFare,
    'distance_km':          distanceKm,
    'user_name':            userName,
    'user_phone':           userPhone,
  };

  AmbulanceRequest copyWith({
    RequestStatus? status,
    String? driverId,
    String? driverName,
    String? driverPhone,
    double? driverLat,
    double? driverLng,
  }) =>
      AmbulanceRequest(
        id: id,
        userFirebaseUid: userFirebaseUid,
        driverId: driverId ?? this.driverId,
        status: status ?? this.status,
        ambulanceType: ambulanceType,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        destinationAddress: destinationAddress,
        estimatedFare: estimatedFare,
        distanceKm: distanceKm,
        userName: userName,
        userPhone: userPhone,
        createdAt: createdAt,
        acceptedAt: acceptedAt,
        completedAt: completedAt,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        driverLat: driverLat ?? this.driverLat,
        driverLng: driverLng ?? this.driverLng,
      );
}

// ──────────────────────────────────────────────────────────────────────────────
// DriverProfile  ←→  drivers table
// ──────────────────────────────────────────────────────────────────────────────
class DriverProfile {
  final String id; // uuid
  final String firebaseUid;
  final String name;
  final String phone;
  final String vehicleType;
  final String vehicleNumber;
  final bool isOnline;
  final bool isApproved;
  final double? currentLat;
  final double? currentLng;
  final String? currentRequestId;

  const DriverProfile({
    required this.id,
    required this.firebaseUid,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.isOnline,
    required this.isApproved,
    this.currentLat,
    this.currentLng,
    this.currentRequestId,
  });

  factory DriverProfile.fromMap(Map<String, dynamic> map) => DriverProfile(
        id:               map['id'] as String,
        firebaseUid:      map['firebase_uid'] as String,
        name:             map['name'] as String,
        phone:            map['phone'] as String,
        vehicleType:      map['vehicle_type'] as String,
        vehicleNumber:    map['vehicle_number'] as String,
        isOnline:         map['is_online'] as bool? ?? false,
        isApproved:       map['is_approved'] as bool? ?? false,
        currentLat:       map['current_lat'] != null
                            ? (map['current_lat'] as num).toDouble()
                            : null,
        currentLng:       map['current_lng'] != null
                            ? (map['current_lng'] as num).toDouble()
                            : null,
        currentRequestId: map['current_request_id'] as String?,
      );
}
