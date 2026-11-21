import 'dart:math' as math;

class IntersectionTrafficLight {
  const IntersectionTrafficLight({
    required this.id,
    required this.direction,
    this.controllerId,
    this.state = 'UNKNOWN',
  });

  final String id;
  final String direction;
  final String? controllerId;
  final String state;

  Map<String, dynamic> toMap() => {
    'id': id,
    'direction': direction,
    'controllerId': controllerId,
    'state': state,
  };
}

class IntersectionPoint {
  const IntersectionPoint({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.plusCode = '',
    this.isActive = true,
    this.trafficLights = const {},
  });

  static const emergencyRadiusMeters = 500.0;

  /// Escape requests target the light itself, so they are allowed from
  /// farther away than the automatic along-route preemption trigger
  /// ([emergencyRadiusMeters]). Any intersection in this range can be
  /// chosen — no assigned traffic officer is required.
  static const escapeRequestRadiusMeters = 1000.0;

  // VGX3+G39 recovered relative to Khulna: 7MJFVGX3+G39 (Durbar Bangla, KUET).
  static const khulna = IntersectionPoint(
    id: 'khulna_durbar_bangla',
    name: 'Durbar Bangla, KUET, Khulna',
    city: 'Khulna',
    latitude: 22.8987875,
    longitude: 89.502734375,
    plusCode: 'VGX3+G39',
  );

  static const moylapota = IntersectionPoint(
    id: 'khulna_moylapota_mor',
    name: 'Moylapota Mor',
    city: 'Khulna',
    latitude: 22.8351875,
    longitude: 89.5381875,
    plusCode: 'RGPQ+37',
  );

  static const royal = IntersectionPoint(
    id: 'khulna_royal_mor',
    name: 'Royal Mor',
    city: 'Khulna',
    latitude: 22.8102625,
    longitude: 89.562265625,
    plusCode: 'RH66+4W2',
  );

  static const shibbari = IntersectionPoint(
    id: 'khulna_shibbari_mor',
    name: 'Shibbari Mor',
    city: 'Khulna',
    latitude: 22.8221875,
    longitude: 89.5526875,
    plusCode: 'RHC3+V3',
  );

  static const khulnaIntersections = [khulna, moylapota, royal, shibbari];
  static const directions = ['north', 'east', 'south', 'west'];

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final String plusCode;
  final bool isActive;
  final Map<String, IntersectionTrafficLight> trafficLights;

  int get wayCount => directions.length;
  int get trafficLightCount => directions.length;

  // Missing legacy entries are unconfigured, never fabricated live colors.
  Map<String, IntersectionTrafficLight> get lights => {
    for (final direction in directions)
      direction:
          trafficLights[direction] ??
          IntersectionTrafficLight(
            id: '${id}_$direction',
            direction: direction,
          ),
  };

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
      trafficLights: {
        for (final direction in directions)
          if (data['trafficLights'] is Map &&
              (data['trafficLights'] as Map)[direction] is Map)
            direction: _decodeLight(
              id,
              direction,
              (data['trafficLights'] as Map)[direction] as Map,
            ),
      },
    );
  }

  static IntersectionTrafficLight _decodeLight(
    String id,
    String direction,
    Map data,
  ) => IntersectionTrafficLight(
    id: data['id'] as String? ?? '${id}_$direction',
    direction: direction,
    controllerId: data['controllerId'] as String?,
    state: data['state'] as String? ?? 'UNKNOWN',
  );

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
    'wayCount': wayCount,
    'trafficLightCount': trafficLightCount,
    'trafficLights': {
      for (final entry in lights.entries) entry.key: entry.value.toMap(),
    },
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
      isActive && distanceFrom(lat, lng) <= escapeRequestRadiusMeters;

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
