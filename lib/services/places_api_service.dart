import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.description});
  final String placeId;
  final String description;
}

class NearbyPlaceResult {
  const NearbyPlaceResult({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.isOpen,
    required this.types,
    this.phone,
  });

  final String id;
  final String name;
  final String address;
  final LatLng location;
  final bool? isOpen;
  final List<String> types;
  final String? phone;
}

class _TransientOverpassException extends http.ClientException {
  _TransientOverpassException(super.message, super.uri);
}

class PlacesApiService {
  static const _channel = MethodChannel('e_ambulance/places');
  static const _userAgent = 'EAmbulanceApp/1.0 (contact@ambulance.bd)';
  static const double nearbyRadiusMeters = 15000.0;
  static const _nearbyTimeout = Duration(seconds: 45);

  PlacesApiService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  bool get isConfigured => true;

  /// Caller owns injected clients.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required LatLng bias,
  }) async {
    final trimmed = input.trim();
    if (trimmed.length < 2) return const [];

    // Try native Google Places first.
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'autocomplete',
        <String, dynamic>{
          'query': trimmed,
          'latitude': bias.latitude,
          'longitude': bias.longitude,
        },
      );
      final list = (raw ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => PlaceSuggestion(
              placeId: item['placeId'] as String? ?? '',
              description: item['description'] as String? ?? '',
            ),
          )
          .where((p) => p.placeId.isNotEmpty && p.description.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // Fallback: Nominatim.
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'q': trimmed,
        'countrycodes': 'bd',
        'addressdetails': '1',
        'limit': '8',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map((item) {
                return PlaceSuggestion(
                  placeId: item['place_id']?.toString() ?? '',
                  description: item['display_name']?.toString() ?? '',
                );
              })
              .where((p) => p.description.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    return const [];
  }

  Future<NearbyPlaceResult?> getPlace(String placeId) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'details',
        <String, dynamic>{'placeId': placeId},
      );
      return raw == null ? null : _decodePlace(raw);
    } catch (_) {
      return null;
    }
  }

  /// Finds hospitals/pharmacies within fixed 15 km. radiusMeters kept for compat only.
  /// Empty/failed native searches fall back to OSM; OSM failures throw.
  Future<List<NearbyPlaceResult>> nearby({
    required LatLng center,
    required String type,
    required double radiusMeters,
  }) async {
    if (type != 'hospital' && type != 'pharmacy') {
      throw ArgumentError.value(type, 'type', 'Expected hospital or pharmacy');
    }
    if (!_validCoordinates(center.latitude, center.longitude)) {
      throw ArgumentError.value(center, 'center', 'Invalid coordinates');
    }
    return _nearby(center: center, type: type).timeout(
      _nearbyTimeout,
      onTimeout: () => throw TimeoutException(
        'Nearby places search timed out after 45 seconds.',
        _nearbyTimeout,
      ),
    );
  }

  Future<List<NearbyPlaceResult>> _nearby({
    required LatLng center,
    required String type,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('nearby', <String, dynamic>{
            'type': type,
            'latitude': center.latitude,
            'longitude': center.longitude,
            'radiusMeters': nearbyRadiusMeters,
          })
          .timeout(const Duration(seconds: 5));
      final places = raw?['places'];
      if (places is List) {
        final results = _normalizeNearby(
          places.whereType<Map>().map(_decodeNativeNearby).nonNulls,
          center: center,
          type: type,
        );
        if (results.isNotEmpty) return results;
      }
    } catch (_) {
      // Missing plugin, Google SDK failure, or invalid native response: use OSM.
    }
    return _fetchOsmNearby(center: center, type: type);
  }

  Future<List<NearbyPlaceResult>> _fetchOsmNearby({
    required LatLng center,
    required String type,
  }) async {
    final around =
        'around:${nearbyRadiusMeters.toInt()},'
        '${center.latitude},${center.longitude}';
    final query =
        '[out:json][timeout:12];('
        'nwr["amenity"="$type"]($around);'
        '${type == 'hospital' ? 'nwr["healthcare"="hospital"]($around);' : ''}'
        ');out center tags;';
    final primary = Uri.https('overpass-api.de', '/api/interpreter');
    final mirror = Uri.https('overpass.private.coffee', '/api/interpreter');
    late List<dynamic> elements;
    try {
      elements = await _queryOverpass(
        primary,
        query,
        const Duration(seconds: 15),
      );
    } on _TransientOverpassException catch (primaryError) {
      // Retry only transient failures, without changing coverage or query.
      try {
        elements = await _queryOverpass(
          mirror,
          query,
          const Duration(seconds: 20),
        );
      } on Exception catch (mirrorError) {
        final message =
            'Overpass nearby places search failed on both endpoints. '
            '${primary.host}: $primaryError; ${mirror.host}: $mirrorError';
        if (mirrorError is FormatException) throw FormatException(message);
        throw http.ClientException(message, mirror);
      }
    }
    return _normalizeNearby(
      elements.whereType<Map>().map(_decodeOsmNearby).nonNulls,
      center: center,
      type: type,
    );
  }

  Future<List<dynamic>> _queryOverpass(
    Uri uri,
    String query,
    Duration timeout,
  ) async {
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
            body: {'data': query},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw _TransientOverpassException(
        'Overpass nearby places request timed out after ${timeout.inSeconds} seconds.',
        uri,
      );
    } on http.ClientException catch (error) {
      throw _TransientOverpassException(
        'Overpass nearby places request failed: ${error.message}',
        uri,
      );
    }
    if (response.statusCode != 200) {
      final message =
          'Overpass nearby places request failed (HTTP ${response.statusCode}).';
      if (response.statusCode == 408 ||
          response.statusCode == 429 ||
          (response.statusCode >= 500 && response.statusCode < 600)) {
        throw _TransientOverpassException(message, uri);
      }
      throw http.ClientException(message, uri);
    }

    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const FormatException('Overpass returned invalid JSON.');
    }
    // Overpass can report runtime errors (including timeouts) with HTTP 200,
    // sometimes without an elements list. Never treat those as empty coverage.
    if (data is Map && data['remark'] != null) {
      throw _TransientOverpassException(
        'Overpass query failed: ${data['remark']}',
        uri,
      );
    }
    if (data is! Map || data['elements'] is! List) {
      throw const FormatException(
        'Overpass returned an invalid response: expected an elements list.',
      );
    }
    return data['elements'] as List<dynamic>;
  }

  NearbyPlaceResult? _decodeNativeNearby(Map data) {
    final name = _placeName(data['name']);
    final location = _location(data['latitude'], data['longitude']);
    final id = _text(data['id']);
    if (name == null || location == null || id == null) return null;
    return NearbyPlaceResult(
      id: id,
      name: name,
      address: _text(data['address']) ?? '',
      location: location,
      isOpen: data['isOpen'] is bool ? data['isOpen'] as bool : null,
      types: data['types'] is List
          ? (data['types'] as List).whereType<String>().toList()
          : const [],
      phone: _text(data['phone']),
    );
  }

  NearbyPlaceResult? _decodeOsmNearby(Map data) {
    final tags = data['tags'];
    final osmType = data['type'];
    final id = data['id'];
    if (tags is! Map ||
        !const ['node', 'way', 'relation'].contains(osmType) ||
        id is! int ||
        id <= 0) {
      return null;
    }
    final name =
        _placeName(tags['name']) ??
        _placeName(tags['name:en']) ??
        _placeName(tags['name:bn']);
    final coordinates = osmType == 'node' ? data : data['center'];
    if (name == null || coordinates is! Map) return null;
    final location = _location(coordinates['lat'], coordinates['lon']);
    if (location == null) return null;
    final types = <String>{
      if (_text(tags['amenity']) case final String amenity) amenity,
      if (_text(tags['healthcare']) case final String healthcare) healthcare,
    }.toList();
    final address =
        _text(tags['addr:full']) ??
        [
          tags['addr:housenumber'],
          tags['addr:street'],
          tags['addr:suburb'],
          tags['addr:city'] ?? tags['addr:town'] ?? tags['addr:village'],
          tags['addr:postcode'],
        ].map(_text).nonNulls.join(', ');
    return NearbyPlaceResult(
      id: 'osm:$osmType:$id',
      name: name,
      address: address,
      location: location,
      isOpen: _text(tags['opening_hours']) == '24/7' ? true : null,
      types: types,
      phone: _text(tags['phone']) ?? _text(tags['contact:phone']),
    );
  }

  List<NearbyPlaceResult> _normalizeNearby(
    Iterable<NearbyPlaceResult> places, {
    required LatLng center,
    required String type,
  }) {
    final sorted =
        places.where((place) {
          if (!place.types.contains(type)) return false;
          if (type == 'hospital' &&
              place.types.any(
                (value) => const ['clinic', 'pharmacy'].contains(value),
              )) {
            return false;
          }
          return _haversineDistance(center, place.location) <=
              nearbyRadiusMeters;
        }).toList()..sort(
          (a, b) => _haversineDistance(
            center,
            a.location,
          ).compareTo(_haversineDistance(center, b.location)),
        );
    final results = <NearbyPlaceResult>[];
    final ids = <String>{};
    for (final place in sorted) {
      if (!ids.add(place.id)) continue;
      // OSM often maps the same facility as both a building and an entrance node.
      if (results.any(
        (existing) =>
            _nameKey(existing.name) == _nameKey(place.name) &&
            _haversineDistance(existing.location, place.location) <= 100,
      )) {
        continue;
      }
      results.add(place);
    }
    return results;
  }

  String? _text(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  String _nameKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String? _placeName(dynamic value) {
    final name = _text(value);
    if (name == null ||
        !RegExp(r'\p{L}', unicode: true).hasMatch(name) ||
        const [
          'hospital',
          'pharmacy',
          'clinic',
          'unnamed place',
          'unknown',
          'unnamed hospital',
          'unnamed pharmacy',
        ].contains(_nameKey(name))) {
      return null;
    }
    return name;
  }

  bool _validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  LatLng? _location(dynamic latitude, dynamic longitude) {
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    // Validate before LatLng can clamp latitude or wrap longitude.
    return _validCoordinates(lat, lng) ? LatLng(lat, lng) : null;
  }

  NearbyPlaceResult _decodePlace(Map<dynamic, dynamic> data) {
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw const FormatException('Place has no coordinates.');
    }
    return NearbyPlaceResult(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed place',
      address: data['address'] as String? ?? 'Address unavailable',
      location: LatLng(latitude, longitude),
      isOpen: null,
      types: (data['types'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      phone: data['phone'] as String?,
    );
  }

  double _haversineDistance(LatLng p1, LatLng p2) {
    const r = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180.0;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180.0;
    final lat1 = p1.latitude * math.pi / 180.0;
    final lat2 = p2.latitude * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}
