import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapSearchSuggestion {
  const MapSearchSuggestion({
    required this.displayName,
    required this.location,
  });

  final String displayName;
  final LatLng location;
}

class DrivingRoute {
  const DrivingRoute({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
}

class MapSearchService {
  static const _userAgent = 'com.example.ambulance_app';

  Future<List<MapSearchSuggestion>> search(String query) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      <String, String>{
        'format': 'json',
        'q': query.trim(),
        'countrycodes': 'bd',
        'addressdetails': '1',
        'limit': '6',
      },
    );
    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw HttpException('Nominatim returned ${response.statusCode}.');
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      throw const FormatException('Invalid Nominatim response.');
    }
    return data.whereType<Map<String, dynamic>>().map((item) {
      final latitude = double.tryParse(item['lat']?.toString() ?? '');
      final longitude = double.tryParse(item['lon']?.toString() ?? '');
      final displayName = item['display_name']?.toString();
      if (latitude == null ||
          longitude == null ||
          displayName == null ||
          displayName.isEmpty) {
        throw const FormatException(
          'Nominatim result has incomplete coordinates.',
        );
      }
      return MapSearchSuggestion(
        displayName: displayName,
        location: LatLng(latitude, longitude),
      );
    }).toList();
  }

  Future<DrivingRoute> getDrivingRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}',
      <String, String>{'overview': 'full', 'geometries': 'geojson'},
    );
    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw HttpException('OSRM returned ${response.statusCode}.');
    }

    final data = jsonDecode(response.body);
    final routes = data is Map<String, dynamic> ? data['routes'] : null;
    if (routes is! List ||
        routes.isEmpty ||
        routes.first is! Map<String, dynamic>) {
      throw const FormatException('OSRM returned no routes.');
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'];
    final coordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    final distanceInMeters = (route['distance'] as num?)?.toDouble();
    final durationInSeconds = (route['duration'] as num?)?.toDouble();
    if (coordinates is! List ||
        distanceInMeters == null ||
        durationInSeconds == null) {
      throw const FormatException('OSRM route is incomplete.');
    }

    final points = coordinates.whereType<List<dynamic>>().map((coordinate) {
      if (coordinate.length < 2 ||
          coordinate[0] is! num ||
          coordinate[1] is! num) {
        throw const FormatException('OSRM geometry is invalid.');
      }
      return LatLng(
        (coordinate[1] as num).toDouble(),
        (coordinate[0] as num).toDouble(),
      );
    }).toList();
    if (points.isEmpty) {
      throw const FormatException('OSRM route has no geometry.');
    }

    return DrivingRoute(
      points: points,
      distanceKm: distanceInMeters / 1000,
      durationMinutes: (durationInSeconds / 60).round(),
    );
  }

  void dispose() {}
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
