import 'dart:convert';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

/// Driving route from Google Directions + along-route math for signal trigger.
/// Straight-line radius can't answer "junction on path within N m ahead".
class RouteService {
  RouteService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Full route geometry (all steps/legs). Throws on failure; callers fall back to radius geofence.
  Future<List<LatLng>> fetchRoutePoints({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'region': 'bd',
      'key': AppConfig.googleMapsApiKey,
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('Google Directions returned ${response.statusCode}.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['status'] != 'OK') {
      throw const FormatException('Google Directions returned no route.');
    }
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw const FormatException('Google Directions returned no route.');
    }
    final route = routes.first as Map<String, dynamic>;
    final legs = route['legs'];
    final points = <LatLng>[];
    if (legs is List) {
      for (final leg in legs.whereType<Map<String, dynamic>>()) {
        final steps = leg['steps'];
        if (steps is! List) continue;
        for (final step in steps.whereType<Map<String, dynamic>>()) {
          final polyline = step['polyline'];
          final encoded = polyline is Map<String, dynamic>
              ? polyline['points']
              : null;
          if (encoded is String && encoded.isNotEmpty) {
            points.addAll(decodePolyline(encoded));
          }
        }
      }
    }
    if (points.length < 2) {
      // Fallback: the (simplified) overview geometry.
      final overview = route['overview_polyline'];
      final encoded =
          overview is Map<String, dynamic> ? overview['points'] : null;
      if (encoded is String && encoded.isNotEmpty) {
        points
          ..clear()
          ..addAll(decodePolyline(encoded));
      }
    }
    if (points.length < 2) {
      throw const FormatException('Google Directions returned no geometry.');
    }
    return points;
  }

  /// Decode Google encoded polyline (1e5) to lat/lng.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Position relative to route: alongMeters + crossMeters (equirectangular projection; city-scale accurate).
  static ({double alongMeters, double crossMeters}) locate({
    required List<LatLng> route,
    required LatLng position,
  }) {
    if (route.length < 2) {
      throw ArgumentError.value(route, 'route', 'Need at least two points');
    }
    final meanLat =
        route.fold<double>(0, (sum, p) => sum + p.latitude) / route.length;
    final cosLat = math.cos(meanLat * math.pi / 180);
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * cosLat;

    double x(LatLng p) => p.longitude * metersPerDegLng;
    double y(LatLng p) => p.latitude * metersPerDegLat;

    final px = x(position);
    final py = y(position);

    var along = 0.0;
    var bestAlong = 0.0;
    var bestCross = double.infinity;

    for (var i = 0; i < route.length - 1; i++) {
      final ax = x(route[i]);
      final ay = y(route[i]);
      final bx = x(route[i + 1]);
      final by = y(route[i + 1]);
      final segLenSq = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);

      var t = segLenSq == 0
          ? 0.0
          : ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / segLenSq;
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * (bx - ax);
      final cy = ay + t * (by - ay);
      final cross = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (cross < bestCross) {
        bestCross = cross;
        bestAlong = along + t * math.sqrt(segLenSq);
      }
      along += math.sqrt(segLenSq);
    }
    return (alongMeters: bestAlong, crossMeters: bestCross);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
