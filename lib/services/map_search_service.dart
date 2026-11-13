import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

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
      '/route/v1/driving/${start.longitude},${start.latitude};'
          '${destination.longitude},${destination.latitude}',
      <String, String>{
        'overview': 'full',
        'geometries': 'geojson',
      },
    );
    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw HttpException('Routing service returned ${response.statusCode}.');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['code'] != 'Ok') {
      final code = data is Map<String, dynamic>
          ? data['code']?.toString()
          : null;
      throw FormatException(
        'Routing service returned no route${code == null ? '' : ' ($code)'}.',
      );
    }

    final routes = data['routes'];
    final route = routes is List && routes.isNotEmpty
        ? routes.first as Map<String, dynamic>?
        : null;
    final geometry = route?['geometry'];
    final coordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    final distanceInMeters = (route?['distance'] as num?)?.toDouble();
    final durationInSeconds = (route?['duration'] as num?)?.toDouble();
    if (coordinates is! List ||
        distanceInMeters == null ||
        durationInSeconds == null) {
      throw const FormatException('Routing service returned an incomplete route.');
    }

    final points = coordinates
        .whereType<List>()
        .where((point) => point.length >= 2)
        .map((point) => LatLng(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
            ))
        .toList();
    if (points.isEmpty) {
      throw const FormatException('Routing service returned no route geometry.');
    }

    var durationMinutes = (durationInSeconds / 60).round();
    try {
      durationMinutes = await _getGoogleDuration(
        start: start,
        destination: destination,
      );
    } on HttpException {
      // Keep the working route estimate when Google Directions is unavailable.
    } on FormatException {
      // Keep the working route estimate when Google returns an incomplete result.
    } on StateError {
      // Keep the working route estimate when the optional Google key is unavailable.
    }

    return DrivingRoute(
      points: points,
      distanceKm: distanceInMeters / 1000,
      durationMinutes: durationMinutes,
    );
  }

  Future<int> _getGoogleDuration({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '${start.latitude},${start.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'region': 'bd',
        'key': AppConfig.googleMapsApiKey,
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException('Google Directions returned ${response.statusCode}.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['status'] != 'OK') {
      throw const FormatException('Google Directions returned no duration.');
    }
    final routes = data['routes'];
    final legs = routes is List &&
            routes.isNotEmpty &&
            routes.first is Map<String, dynamic>
        ? (routes.first as Map<String, dynamic>)['legs']
        : null;
    final duration = legs is List &&
            legs.isNotEmpty &&
            legs.first is Map<String, dynamic>
        ? (legs.first as Map<String, dynamic>)['duration']
        : null;
    final seconds = duration is Map<String, dynamic>
        ? (duration['value'] as num?)?.toDouble()
        : null;
    if (seconds == null) {
      throw const FormatException('Google Directions returned no duration.');
    }
    return (seconds / 60).ceil();
  }

  void dispose() {}
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
