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
    final routes = data is Map<String, dynamic> ? data['routes'] : null;
    if (routes is! List ||
        routes.isEmpty ||
        routes.first is! Map<String, dynamic>) {
      throw const FormatException('Google Directions returned no routes.');
    }
    final route = routes.first as Map<String, dynamic>;
    final overview = route['overview_polyline'];
    final encoded = overview is Map<String, dynamic>
        ? overview['points']?.toString()
        : null;
    final legs = route['legs'];
    final leg = legs is List && legs.isNotEmpty && legs.first is Map<String, dynamic>
        ? legs.first as Map<String, dynamic>
        : null;
    final distance = leg?['distance'];
    final duration = leg?['duration'];
    final distanceInMeters = distance is Map<String, dynamic>
        ? (distance['value'] as num?)?.toDouble()
        : null;
    final durationInSeconds = duration is Map<String, dynamic>
        ? (duration['value'] as num?)?.toDouble()
        : null;
    if (encoded == null ||
        distanceInMeters == null ||
        durationInSeconds == null) {
      throw const FormatException('Google Directions route is incomplete.');
    }

    final points = _decodePolyline(encoded);
    if (points.isEmpty) {
      throw const FormatException('Google Directions route has no geometry.');
    }

    return DrivingRoute(
      points: points,
      distanceKm: distanceInMeters / 1000,
      durationMinutes: (durationInSeconds / 60).round(),
    );
  }

  void dispose() {}

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        if (index >= encoded.length) return points;
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        if (index >= encoded.length) return points;
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(LatLng(latitude / 100000, longitude / 100000));
    }
    return points;
  }
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
