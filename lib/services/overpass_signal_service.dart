import 'dart:convert';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class TrafficSignal {
  const TrafficSignal({
    required this.id,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final double latitude;
  final double longitude;

  LatLng get location => LatLng(latitude, longitude);
}

class OverpassSignalService {
  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<TrafficSignal>> findSignalsAlongRoute(
    List<LatLng> routePoints,
  ) async {
    if (routePoints.isEmpty) return const [];
    final latitudes = routePoints.map((point) => point.latitude);
    final longitudes = routePoints.map((point) => point.longitude);
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

    final query = '''
[out:json][timeout:25];
node["highway"="traffic_signals"]($minLat,$minLng,$maxLat,$maxLng);
out body;
''';
    final response = await http.post(
      Uri.parse(_endpoint),
      body: {'data': query},
      headers: const {'User-Agent': 'com.example.ambulance_app'},
    );
    if (response.statusCode != 200) {
      throw StateError('Overpass returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final elements = decoded is Map<String, dynamic> ? decoded['elements'] : null;
    if (elements is! List) {
      throw const FormatException('Invalid Overpass response.');
    }
    return elements.whereType<Map<String, dynamic>>().map((element) {
      final lat = (element['lat'] as num?)?.toDouble();
      final lon = (element['lon'] as num?)?.toDouble();
      final id = element['id']?.toString();
      if (lat == null || lon == null || id == null) {
        throw const FormatException('Overpass signal has incomplete coordinates.');
      }
      return TrafficSignal(id: id, latitude: lat, longitude: lon);
    }).toList();
  }
}

bool isApproachingIntersection({
  required double driverLat,
  required double driverLng,
  required double driverHeading,
  required double signalLat,
  required double signalLng,
}) {
  final distance = _distanceBetween(
    driverLat,
    driverLng,
    signalLat,
    signalLng,
  );
  if (distance > 2000) return false;

  final bearing = _bearingBetween(
    driverLat,
    driverLng,
    signalLat,
    signalLng,
  );
  final angleDifference = (bearing - driverHeading + 540) % 360 - 180;
  return angleDifference.abs() <= 60;
}

double _distanceBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _bearingBetween(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _radians(lat1);
  final phi2 = _radians(lat2);
  final lambda = _radians(lng2 - lng1);
  final y = math.sin(lambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(lambda);
  return (_degrees(math.atan2(y, x)) + 360) % 360;
}

double _radians(double value) => value * 3.141592653589793 / 180;
double _degrees(double value) => value * 180 / 3.141592653589793;
