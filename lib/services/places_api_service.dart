import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.description});
  final String placeId;
  final String description;
}

class NearbyPlaceResult {
  const NearbyPlaceResult({required this.id, required this.name, required this.address, required this.location, required this.isOpen, required this.types});
  final String id;
  final String name;
  final String address;
  final LatLng location;
  final bool? isOpen;
  final List<String> types;
}

class PlacesApiService {
  static const _channel = MethodChannel('e_ambulance/places');

  bool get isConfigured => true;
  void dispose() {}

  Future<List<PlaceSuggestion>> autocomplete({required String input, required LatLng bias}) async {
    if (input.trim().length < 2) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('autocomplete', <String, dynamic>{
      'query': input.trim(),
      'latitude': bias.latitude,
      'longitude': bias.longitude,
    });
    return (raw ?? const []).whereType<Map<dynamic, dynamic>>().map((item) => PlaceSuggestion(
          placeId: item['placeId'] as String,
          description: item['description'] as String,
        )).toList();
  }

  Future<NearbyPlaceResult?> getPlace(String placeId) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('details', <String, dynamic>{'placeId': placeId});
    return raw == null ? null : _decodePlace(raw);
  }

  Future<List<NearbyPlaceResult>> nearby({required LatLng center, required String type}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('nearby', <String, dynamic>{
      'type': type,
      'latitude': center.latitude,
      'longitude': center.longitude,
    });
    final places = raw?['places'] as List<dynamic>? ?? const [];
    final results = places.whereType<Map<dynamic, dynamic>>().map(_decodePlace).toList();
    results.sort((a, b) => _distance(center, a.location).compareTo(_distance(center, b.location)));
    return results;
  }

  NearbyPlaceResult _decodePlace(Map<dynamic, dynamic> data) {
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) throw const FormatException('Place has no coordinates.');
    return NearbyPlaceResult(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed place',
      address: data['address'] as String? ?? 'Address unavailable',
      location: LatLng(latitude, longitude),
      isOpen: null,
      types: (data['types'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    );
  }

  double _distance(LatLng first, LatLng second) {
    final latitudeDelta = (first.latitude - second.latitude).abs();
    final longitudeDelta = (first.longitude - second.longitude).abs();
    return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta;
  }
}
