import 'dart:math' as math;

class IntersectionPoint {
  const IntersectionPoint({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.plusCode = '',
    this.isActive = true,
  });

  static const emergencyRadiusMeters = 500.0;

  // VGX3+G39 recovered relative to Khulna: 7MJFVGX3+G39.
  static const khulna = IntersectionPoint(
    id: 'khulna_vgx3_g39',
    name: 'VGX3+G39, Khulna',
    city: 'Khulna',
    latitude: 22.8987875,
    longitude: 89.502734375,
    plusCode: 'VGX3+G39',
  );

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final String plusCode;
  final bool isActive;

  factory IntersectionPoint.fromMap(String id, Map<String, dynamic> data) {
    final latitude = (data['latitude'] as num).toDouble();
    final longitude = (data['longitude'] as num).toDouble();
    validateCoordinates(latitude, longitude);
    return IntersectionPoint(
      id: id,
      name: data['name'] as String,
      city: data['city'] as String,
      latitude: latitude,
      longitude: longitude,
      plusCode: data['plusCode'] as String? ?? '',
      isActive: data['isActive'] == true,
    );
  }

  static void validateCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Valid latitude and longitude are required.');
    }
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'city': city,
    'latitude': latitude,
    'longitude': longitude,
    'plusCode': plusCode,
    'isActive': isActive,
  };

  double distanceFrom(double lat, double lng) {
    validateCoordinates(lat, lng);
    const radians = math.pi / 180;
    final dLat = (latitude - lat) * radians;
    final dLng = (longitude - lng) * radians;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat * radians) *
            math.cos(latitude * radians) *
            math.pow(math.sin(dLng / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  bool canRequestFrom(double lat, double lng) =>
      isActive && distanceFrom(lat, lng) <= emergencyRadiusMeters;

  bool matchesOfficer({
    String? intersectionId,
    String? assignedIntersection,
    double? latitude,
    double? longitude,
  }) {
    if (intersectionId != null && intersectionId.isNotEmpty) {
      return intersectionId == id;
    }
    if (latitude != null && longitude != null) {
      return distanceFrom(latitude, longitude) <= 250;
    }
    final assignment = assignedIntersection?.trim().toLowerCase();
    if (assignment == null || assignment.isEmpty) return false;
    return assignment == name.toLowerCase() ||
        (plusCode.isNotEmpty &&
            (assignment == plusCode.toLowerCase() ||
                assignment ==
                    '${plusCode.toLowerCase()}, ${city.toLowerCase()}'));
  }
}
