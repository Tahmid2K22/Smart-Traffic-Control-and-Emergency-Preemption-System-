import 'dart:math' as math;

import 'package:e_ambulance/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('decodePolyline', () {
    test('decodes the canonical example', () {
      // Classic sample from the Google polyline docs.
      final points = RouteService.decodePolyline('_p~iF~ps|U_ulLnnqC');
      expect(points, hasLength(2));
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[1].latitude, closeTo(40.7, 1e-5));
      expect(points[1].longitude, closeTo(-120.95, 1e-5));
    });

    test('is lossless for arbitrary points', () {
      const original = [
        LatLng(22.8987875, 89.502734375),
        LatLng(22.9000001, 89.5012345),
        LatLng(22.8123456, 89.562265625),
      ];
      // Re-encode with the standard algorithm to round-trip the decoder.
      final encoded = _encode(original);
      final decoded = RouteService.decodePolyline(encoded);
      expect(decoded, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(decoded[i].latitude, closeTo(original[i].latitude, 1e-5));
        expect(decoded[i].longitude, closeTo(original[i].longitude, 1e-5));
      }
    });
  });

  group('locate (along-route math)', () {
    // A straight 3-point route heading due north from (22.90, 89.50),
    // 1000 m per segment.
    final route = [
      const LatLng(22.90, 89.50),
      const LatLng(22.90 + 1000 / 111320, 89.50),
      const LatLng(22.90 + 2000 / 111320, 89.50),
    ];

    test('ambulance at the route start is ~0 m along, ~0 m off', () {
      final r = RouteService.locate(route: route, position: route.first);
      expect(r.alongMeters, closeTo(0, 1));
      expect(r.crossMeters, closeTo(0, 1));
    });

    test('junction 1.5 km along the route reports its offset', () {
      final junction = const LatLng(22.90, 89.50).plusNorth(1500);
      final r = RouteService.locate(route: route, position: junction);
      expect(r.alongMeters, closeTo(1500, 2));
      expect(r.crossMeters, closeTo(0, 2));
    });

    test('a junction far off the route has a large cross distance', () {
      // 1500 m north AND 500 m east — beside the route, not on it.
      final junction = LatLng(
        22.90 + 1500 / 111320,
        89.50 + 500 / (111320 * math.cos(22.90 * math.pi / 180)),
      );
      final r = RouteService.locate(route: route, position: junction);
      expect(r.alongMeters, closeTo(1500, 2));
      expect(r.crossMeters, closeTo(500, 5));
    });

    test('ambulance past the junction reports a larger along distance', () {
      final junctionAlong = RouteService.locate(
        route: route,
        position: const LatLng(22.90, 89.50).plusNorth(1200),
      );
      final ambulanceAlong = RouteService.locate(
        route: route,
        position: const LatLng(22.90, 89.50).plusNorth(1400),
      );
      expect(ambulanceAlong.alongMeters, greaterThan(junctionAlong.alongMeters));
    });
  });
}

extension on LatLng {
  /// Moves [meters] due north (used to build deterministic fixtures).
  LatLng plusNorth(double meters) =>
      LatLng(latitude + meters / 111320, longitude);
}

/// Minimal reference encoder (standard polyline algorithm) for round-trips.
String _encode(List<LatLng> points) {
  String encodeValue(int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    final out = StringBuffer();
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
    return out.toString();
  }

  var lastLat = 0;
  var lastLng = 0;
  final out = StringBuffer();
  for (final point in points) {
    final lat = (point.latitude * 1e5).round();
    final lng = (point.longitude * 1e5).round();
    out.write(encodeValue(lat - lastLat));
    out.write(encodeValue(lng - lastLng));
    lastLat = lat;
    lastLng = lng;
  }
  return out.toString();
}
